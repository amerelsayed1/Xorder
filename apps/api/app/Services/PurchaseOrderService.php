<?php

namespace App\Services;

use App\Enums\PurchaseCloseReason;
use App\Enums\PurchaseStatus;
use App\Exceptions\PurchasingRefusal;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\StockItem;
use App\Models\Supplier;
use App\Models\Unit;
use App\Models\User;
use App\Support\StockCosting;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * CB-09 slice b: every change a purchase order can undergo apart from
 * receiving (ReceivingService). The platform's PurchaseEngine.
 *
 * Every transition takes a lock on the order row and RE-READS the status
 * under that lock. The caller's model instance is only an id: a status it
 * loaded before somebody else booked a delivery in is never trusted. That
 * is what closes the till's gap (design §10 C2), where setStatus updated
 * with no status precondition and the only guard was which button showed.
 *
 *   edit    draft only
 *   send    draft only, with at least one line, to an active supplier;
 *           numbers it, snapshots the totals, stamps ordered_at
 *   cancel  draft or sent only; refused once anything has arrived
 *
 * On SQLite lockForUpdate is a no-op, but SQLite allows one writer at a
 * time, so check-then-write inside a transaction stays serial. PostgreSQL
 * gets the real row lock.
 */
class PurchaseOrderService
{
    public function __construct(private PurchaseSequenceService $sequences) {}

    /** @param array<string,mixed> $data validated StorePurchaseOrderRequest */
    public function create(array $data, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($data, $by) {
            $restaurant = $by->restaurant;
            $supplier = $this->supplierFor($data['supplier_id'], null);

            $order = new PurchaseOrder;
            $order->forceFill([
                'restaurant_id' => $by->restaurant_id,
                'branch_id' => $data['branch_id'],
                'supplier_id' => $supplier->id,
                'supplier_name' => $this->nameOf($supplier->name_en, $supplier->name_ar, $this->language($by)),
                'status' => PurchaseStatus::DRAFT,
                'currency' => $restaurant->currency?->value ?? 'EGP',
                'exponent' => $restaurant->currency?->exponent() ?? 2,
                'expected_at' => $data['expected_at'] ?? null,
                'notes' => $data['notes'] ?? null,
                'created_by' => $by->id,
                'updated_by' => $by->id,
            ])->save();

            $this->writeLines($order, $data['lines'] ?? [], $by);

            AuditLogger::record('purchase_order.created', [
                'auditable' => $order,
                'description' => sprintf('Purchase order draft #%d for "%s" created', $order->id, $order->supplier_name),
                'properties' => ['branch_id' => $order->branch_id, 'lines' => count($data['lines'] ?? [])],
            ]);

            return $order;
        });
    }

    /** Replace a draft's header and lines wholesale, as the till's editor does. */
    public function update(PurchaseOrder $order, array $data, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $data, $by) {
            $locked = $this->lock($order);

            if (! $locked->status->isEditable()) {
                throw PurchasingRefusal::conflict('PO_NOT_EDITABLE', 'not_editable', ['status' => $this->statusLabel($locked->status)]);
            }

            $supplier = $this->supplierFor($data['supplier_id'], $locked);

            $locked->forceFill([
                'branch_id' => $data['branch_id'],
                'supplier_id' => $supplier->id,
                'supplier_name' => $supplier->id === $locked->supplier_id
                    ? $locked->supplier_name
                    : $this->nameOf($supplier->name_en, $supplier->name_ar, $this->language($by)),
                'expected_at' => $data['expected_at'] ?? null,
                'notes' => $data['notes'] ?? null,
                'updated_by' => $by->id,
            ])->save();

            $previous = $locked->lines()->get();
            PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $locked->id)->delete();
            $this->writeLines($locked, $data['lines'] ?? [], $by, $previous);

            AuditLogger::record('purchase_order.updated', [
                'auditable' => $locked,
                'description' => sprintf('Purchase order draft #%d updated', $locked->id),
                'properties' => ['lines' => count($data['lines'] ?? [])],
            ]);

            return $locked;
        });
    }

    public function send(PurchaseOrder $order, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $by) {
            $locked = $this->lock($order);

            if ($locked->status !== PurchaseStatus::DRAFT) {
                throw PurchasingRefusal::conflict('PO_NOT_DRAFT', 'not_draft', ['status' => $this->statusLabel($locked->status)]);
            }

            $lines = $locked->lines()->get();
            if ($lines->isEmpty()) {
                throw PurchasingRefusal::invalid('PO_HAS_NO_LINES', 'no_lines');
            }

            $supplier = Supplier::withoutGlobalScopes()->whereKey($locked->supplier_id)->first();
            if ($supplier === null || ! $supplier->is_active) {
                throw PurchasingRefusal::invalid('PO_SUPPLIER_RETIRED', 'supplier_retired', [], 'supplier_id');
            }

            $totals = self::totals($lines);
            $restaurant = $by->restaurant;
            $at = now();

            $locked->forceFill([
                // The name on the document is the supplier's name when the
                // document is issued: a rename between draft and send is
                // picked up here, and never again after.
                'supplier_name' => $this->nameOf($supplier->name_en, $supplier->name_ar, $this->language($by)),
                'status' => PurchaseStatus::SENT,
                'reference' => $this->sequences->next($locked->restaurant_id, $at->copy()->setTimezone($restaurant->timezone ?: config('app.timezone'))),
                'ordered_at' => $at,
                'subtotal_minor' => $totals['subtotal_minor'],
                'tax_minor' => $totals['tax_minor'],
                'total_minor' => $totals['total_minor'],
                'updated_by' => $by->id,
            ])->save();

            AuditLogger::record('purchase_order.sent', [
                'auditable' => $locked,
                'description' => sprintf('Purchase order %s sent to "%s"', $locked->reference, $locked->supplier_name),
                'properties' => ['reference' => $locked->reference, 'total_minor' => $locked->total_minor, 'currency' => $locked->currency],
            ]);

            return $locked;
        });
    }

    public function cancel(PurchaseOrder $order, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $by) {
            $locked = $this->lock($order);

            // Re-read under the lock: an order a stale page still shows as
            // "sent" may have had goods booked in since.
            $arrived = PurchaseOrderLine::withoutGlobalScopes()
                ->where('purchase_order_id', $locked->id)
                ->where('received_milli', '>', 0)
                ->exists();

            if (! $locked->status->canCancel() || $arrived) {
                throw PurchasingRefusal::conflict('PO_CANNOT_CANCEL', 'cannot_cancel', ['status' => $this->statusLabel($locked->status)]);
            }

            $from = $locked->status;
            $locked->forceFill(['status' => PurchaseStatus::CANCELLED, 'updated_by' => $by->id])->save();

            AuditLogger::record('purchase_order.cancelled', [
                'auditable' => $locked,
                'description' => sprintf('Purchase order %s cancelled', $locked->reference ?? '#'.$locked->id),
                'properties' => ['from' => $from->value],
            ]);

            return $locked;
        });
    }

    /**
     * CB-09 D11 (owner, 2026-09-13): close a part delivery short. The rest is
     * recorded as not coming and the order is finished.
     *
     *   - Only a PARTIALLY RECEIVED order, re-read under the lock. A sent
     *     order with nothing received is cancelled instead; a draft, a
     *     received or a cancelled order has nothing to close.
     *   - It becomes `received` (the till's five statuses have no other
     *     honest value; its migration 44 allows partially_received →
     *     received for exactly this), stamped closed_short_at/by with a
     *     reason code and an optional note (required for `other`).
     *   - What is not coming is each line's outstanding quantity now. It is
     *     frozen from here: a received order takes no more receipts.
     *   - It NEVER touches stock: no movement is written and no level
     *     changes. What arrived stays booked in at the cost it arrived at.
     */
    public function closeShort(PurchaseOrder $order, PurchaseCloseReason $reason, ?string $note, User $by): PurchaseOrder
    {
        return DB::transaction(function () use ($order, $reason, $note, $by) {
            $locked = $this->lock($order);

            $lines = PurchaseOrderLine::withoutGlobalScopes()
                ->where('purchase_order_id', $locked->id)
                ->orderBy('id')
                ->get(['id', 'ordered_milli', 'received_milli', 'unit_code']);
            $short = $lines->filter(fn ($l) => $l->received_milli < $l->ordered_milli);

            if (! $locked->status->canCloseShort() || $short->isEmpty()) {
                throw PurchasingRefusal::conflict('PO_CANNOT_CLOSE_SHORT', 'cannot_close_short', ['status' => $this->statusLabel($locked->status)]);
            }

            $locked->forceFill([
                'status' => PurchaseStatus::RECEIVED,
                'closed_short_at' => now(),
                'closed_short_by' => $by->id,
                'close_reason' => $reason,
                'close_note' => $note,
                'updated_by' => $by->id,
            ])->save();

            AuditLogger::record('purchase_order.closed_short', [
                'auditable' => $locked,
                'description' => sprintf('Purchase order %s closed short (%s)', $locked->reference, $reason->value),
                'properties' => [
                    'from' => PurchaseStatus::PARTIALLY_RECEIVED->value,
                    'reason' => $reason->value,
                    'note' => $note,
                    'not_coming' => $short->map(fn ($l) => [
                        'line_id' => $l->id,
                        'quantity_milli' => $l->ordered_milli - $l->received_milli,
                        'unit_code' => $l->unit_code,
                    ])->values()->all(),
                ],
            ]);

            return $locked;
        });
    }

    /**
     * What has arrived WITH tax, rounded per rate on the received values: the
     * till's PurchaseOrder.receivedTotal, "the figure a supplier's invoice
     * should say". For comparison beside an invoice only (CB-09 slice c); it
     * never reprices anything.
     */
    public static function receivedTotal(iterable $lines): int
    {
        $net = 0;
        $bases = [];
        foreach ($lines as $line) {
            $amount = StockCosting::costAt((int) $line['received_milli'], (int) $line['unit_cost_minor']);
            $net += $amount;
            $bp = (int) $line['tax_rate_bp'];
            if ($bp > 0) {
                $bases[$bp] = ($bases[$bp] ?? 0) + $amount;
            }
        }

        ksort($bases);
        $tax = 0;
        foreach ($bases as $bp => $base) {
            $tax += StockCosting::percentBp($base, $bp);
        }

        return $net + $tax;
    }

    /**
     * What an order comes to. Tax is rounded PER RATE, not per line and not
     * once at the end: the till's PurchaseOrder.totals.
     *
     * @param  iterable<PurchaseOrderLine|array{ordered_milli:int,unit_cost_minor:int,tax_rate_bp:int}>  $lines
     * @return array{subtotal_minor:int, tax_minor:int, total_minor:int}
     */
    public static function totals(iterable $lines): array
    {
        $subtotal = 0;
        $bases = [];

        foreach ($lines as $line) {
            $amount = StockCosting::costAt((int) $line['ordered_milli'], (int) $line['unit_cost_minor']);
            $subtotal += $amount;
            $bp = (int) $line['tax_rate_bp'];
            if ($bp > 0) {
                $bases[$bp] = ($bases[$bp] ?? 0) + $amount;
            }
        }

        ksort($bases);
        $tax = 0;
        foreach ($bases as $bp => $base) {
            $tax += StockCosting::percentBp($base, $bp);
        }

        return ['subtotal_minor' => $subtotal, 'tax_minor' => $tax, 'total_minor' => $subtotal + $tax];
    }

    /** What has arrived, at the ordered cost, before tax. */
    public static function receivedValue(iterable $lines): int
    {
        $sum = 0;
        foreach ($lines as $line) {
            $sum += StockCosting::costAt((int) $line['received_milli'], (int) $line['unit_cost_minor']);
        }

        return $sum;
    }

    // ------------------------------------------------------------ internals

    private function lock(PurchaseOrder $order): PurchaseOrder
    {
        return PurchaseOrder::withoutGlobalScopes()
            ->where('restaurant_id', $order->restaurant_id)
            ->whereKey($order->id)
            ->lockForUpdate()
            ->firstOrFail();
    }

    /**
     * A retired supplier is refused on a new order, and on a draft that
     * didn't already name it. An order that already names one keeps it.
     */
    private function supplierFor(int $supplierId, ?PurchaseOrder $current): Supplier
    {
        $supplier = Supplier::query()->findOrFail($supplierId);

        if (! $supplier->is_active && $supplier->id !== $current?->supplier_id) {
            throw ValidationException::withMessages(['supplier_id' => __('xorder.purchasing.supplier_retired')]);
        }

        return $supplier;
    }

    /**
     * Write a draft's lines. A stock-item line takes the item's unit (the
     * till's dialog locks it the same way) and, when no description was
     * typed, the item's name as its snapshot. Retired items and units are
     * refused unless this order already carried them; a fraction is refused
     * on a unit that is counted whole.
     *
     * @param  list<array<string,mixed>>  $lines
     * @param  iterable<PurchaseOrderLine>  $previous  the draft's lines before this save
     */
    private function writeLines(PurchaseOrder $order, array $lines, User $by, iterable $previous = []): void
    {
        $keptItems = [];
        $keptUnits = [];
        foreach ($previous as $old) {
            if ($old->stock_item_id) {
                $keptItems[$old->stock_item_id] = true;
            }
            $keptUnits[$old->unit_code] = true;
        }

        $itemIds = array_values(array_unique(array_filter(array_map(fn ($l) => $l['stock_item_id'] ?? null, $lines))));
        sort($itemIds);
        // FOR SHARE, so a unit change on one of these items waits for this
        // draft instead of both reading "not on an open order".
        $items = StockItem::query()->whereIn('id', $itemIds)->orderBy('id')->sharedLock()->get()->keyBy('id');
        $units = Unit::query()->get()->keyBy('code');
        $language = $this->language($by);
        $errors = [];

        foreach (array_values($lines) as $i => $line) {
            $item = isset($line['stock_item_id']) ? $items->get($line['stock_item_id']) : null;

            if ($item !== null && ! $item->is_active && ! isset($keptItems[$item->id])) {
                $errors["lines.$i.stock_item_id"][] = __('xorder.purchasing.stock_item_retired');

                continue;
            }

            $unitCode = $item?->unit_code ?? $line['unit_code'];
            $unit = $units->get($unitCode);

            if ($unit !== null && ! $unit->is_active && ! isset($keptUnits[$unitCode]) && $item === null) {
                $errors["lines.$i.unit_code"][] = __('xorder.purchasing.unit_retired');

                continue;
            }

            if ($unit !== null && ! $unit->allows_fraction && $line['quantity_milli'] % 1000 !== 0) {
                $errors["lines.$i.quantity_milli"][] = __('xorder.purchasing.fraction_not_allowed', ['unit' => $unitCode]);

                continue;
            }

            $description = trim((string) ($line['description'] ?? ''));
            if ($description === '' && $item !== null) {
                $description = $item->displayName($language);
            }

            $row = new PurchaseOrderLine;
            $row->forceFill([
                'restaurant_id' => $order->restaurant_id,
                'purchase_order_id' => $order->id,
                'stock_item_id' => $item?->id,
                'description' => mb_substr($description, 0, 200),
                'sku' => ($line['sku'] ?? null) ?: $item?->sku,
                'ordered_milli' => $line['quantity_milli'],
                'received_milli' => 0,
                'unit_code' => $unitCode,
                'unit_cost_minor' => $line['unit_cost_minor'],
                'tax_rate_bp' => $line['tax_rate_bp'] ?? 0,
                'sort_order' => $i,
            ])->save();
        }

        if ($errors !== []) {
            // Thrown inside the transaction: nothing of this save survives.
            throw ValidationException::withMessages($errors);
        }
    }

    private function language(User $by): string
    {
        $lang = $by->restaurant?->default_language;

        return $lang instanceof \BackedEnum ? $lang->value : (string) ($lang ?: 'en');
    }

    /** Whichever name is set, the business's default language first. */
    private function nameOf(?string $en, ?string $ar, string $preferred): string
    {
        $first = $preferred === 'ar' ? $ar : $en;
        $second = $preferred === 'ar' ? $en : $ar;

        return mb_substr((string) ($first ?: $second), 0, 160);
    }

    private function statusLabel(PurchaseStatus $status): string
    {
        return __('xorder.purchasing.status.'.$status->value);
    }
}
