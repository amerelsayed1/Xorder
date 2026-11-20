<?php

namespace App\Services;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Enums\TableVisitStatus;
use App\Enums\TenantCapability;
use App\Exceptions\WaiterWireException;
use App\Models\BillRequest;
use App\Models\Branch;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderRound;
use App\Models\Restaurant;
use App\Models\TableCheckDraft;
use App\Models\TableVisit;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * POS-BE-033 — the waiter's view of a table: the floor, one table's check, and
 * the operations that change it.
 *
 * What a check is here: the table visit's one NEW order (the same order the QR
 * path appends rounds to) as SENT lines, plus the visit's DRAFT (unsent lines
 * every device at the table shares). Nothing is priced by the caller: draft
 * lines hold ids and quantities, and every read prices them again from the
 * menu through PosPricingEngine; sent lines keep the price they were sent at.
 *
 * `table_visits.check_version` is the compare-and-swap counter: every changing
 * batch bumps it, a stale `version` is refused with CHECK_CHANGED and the
 * current check. A batch is all-or-none (one transaction; any refusal rolls it
 * back).
 */
class WaiterCheckService
{
    private const MAX_QTY = 99;

    public function __construct(
        private readonly PosPricingEngine $pricing,
        private readonly TableVisitService $visits,
    ) {}

    // ---------------------------------------------------------------- reads

    /** @return array<string,mixed> */
    public function floor(Restaurant $restaurant): array
    {
        $tables = DiningTable::query()
            ->where('is_active', true)
            ->with('diningArea')
            ->orderBy('dining_area_id')->orderBy('label')->orderBy('id')
            ->get();

        // A request can outlive its table (`table_id` is nullable, nulled when the
        // table is deleted): skip those, `flip()` raises on a null and would fail
        // the whole floor.
        $asked = BillRequest::query()
            ->whereIn('status', array_map(fn (BillRequestStatus $s) => $s->value,
                array_filter(BillRequestStatus::cases(), fn (BillRequestStatus $s) => $s->isOpen())))
            ->whereNotNull('table_id')
            ->pluck('table_id')->flip();

        $out = [];
        foreach ($tables as $table) {
            /** @var DiningTable $table */
            $check = $this->check($restaurant, $table);
            $hasLines = $check['lines'] !== [];

            $out[] = [
                'id' => $table->id,
                'label' => (string) $table->label,
                'area' => $table->diningArea?->name_en ?: $table->diningArea?->name_ar,
                'seats' => $table->seats_count,
                'state' => $asked->has($table->id) ? 'bill_asked' : ($hasLines ? 'open' : 'free'),
                'total_minor' => $check['total_minor'],
                'items' => (int) array_sum(array_column($check['lines'], 'qty')),
                'guests' => $check['guests'] ?? null,
            ];
        }

        return [
            'currency' => ['code' => $restaurant->currency->value, 'exponent' => $restaurant->currency->exponent()],
            'tables' => array_map(fn (array $t) => array_filter($t, fn ($v) => $v !== null), $out),
        ];
    }

    public function findTable(int $tableId): DiningTable
    {
        $table = DiningTable::query()->where('is_active', true)->find($tableId);

        if ($table === null) {
            throw new WaiterWireException('NOT_FOUND', 404);
        }

        return $table;
    }

    /** @return array<string,mixed> the WaiterCheck of one table */
    public function check(Restaurant $restaurant, DiningTable $table): array
    {
        $visit = $this->openVisit($table);

        return $this->build($restaurant, $table, $visit);
    }

    // ----------------------------------------------------------------- ops

    /**
     * @param  list<array<string,mixed>>  $ops
     * @return array<string,mixed> the priced check after the batch
     */
    public function apply(Restaurant $restaurant, User $user, DiningTable $table, ?int $version, array $ops): array
    {
        if (! $user->holdsTenantCapability(TenantCapability::POS_OPERATE)) {
            throw new WaiterWireException('NOT_PERMITTED', 403, ['reason' => 'pos_operate']);
        }

        $version ??= 0;
        $sentOrder = null;

        try {
            $visit = DB::transaction(function () use ($restaurant, $user, $table, $version, $ops, &$sentOrder) {
                $visit = $this->openVisit($table);

                if ($visit === null) {
                    if ($version > 0) {
                        throw new WaiterWireException('CHECK_CHANGED', 409, [
                            'check' => $this->build($restaurant, $table, null),
                        ]);
                    }
                    $visit = $this->visits->activeForTable($table);
                }

                $visit = TableVisit::withoutGlobalScopes()->whereKey($visit->id)->lockForUpdate()->firstOrFail();

                if ((int) $visit->check_version !== $version) {
                    throw new WaiterWireException('CHECK_CHANGED', 409, [
                        'check' => $this->build($restaurant, $table, $visit),
                    ]);
                }

                $draft = TableCheckDraft::query()->where('table_visit_id', $visit->id)->first()
                    ?? new TableCheckDraft(['lines' => []]);
                $lines = $draft->lines ?? [];
                $guests = $draft->guests;
                $changed = false;

                foreach ($ops as $op) {
                    $kind = is_array($op) ? ($op['op'] ?? null) : null;

                    switch ($kind) {
                        case 'add':
                            $this->opAdd($lines, $op);
                            break;
                        case 'qty':
                            $this->opQty($lines, $op);
                            break;
                        case 'remove':
                            $this->opRemove($lines, $op);
                            break;
                        case 'note':
                            $this->opNote($lines, $op);
                            break;
                        case 'guests':
                            $guests = max(1, min(self::MAX_QTY, (int) ($op['guests'] ?? 1)));
                            break;
                        case 'send':
                            $sentOrder = $this->sendRound($restaurant, $user, $table, $visit, $lines);
                            $lines = [];
                            break;
                        default:
                            throw new WaiterWireException('BAD_REQUEST', 400);
                    }
                    $changed = true;
                }

                if ($changed) {
                    $this->persistDraft($draft, $visit, $restaurant, $lines, $guests);
                    $this->priceOrRefuse($restaurant, $table, $visit, $lines);
                    $visit->forceFill(['check_version' => $visit->check_version + 1])->save();
                }

                return $visit;
            });
        } catch (ValidationException) {
            throw new WaiterWireException('REFUSED', 422, ['reason' => 'invalid_options']);
        }

        if ($sentOrder !== null) {
            $this->notifyKitchen($restaurant, $sentOrder);
        }

        return $this->build($restaurant, $table, $visit->fresh());
    }

    /** @param list<array<string,mixed>> $lines */
    private function opAdd(array &$lines, array $op): void
    {
        $productId = (int) ($op['product_id'] ?? 0);
        $qty = (int) ($op['qty'] ?? 1);
        $optionIds = array_values(array_unique(array_map('intval', (array) ($op['modifier_ids'] ?? []))));
        sort($optionIds);
        $note = isset($op['note']) && is_string($op['note']) && trim($op['note']) !== '' ? mb_substr(trim($op['note']), 0, 200) : null;

        if ($qty < 1 || $qty > self::MAX_QTY) {
            throw new WaiterWireException('REFUSED', 422, ['reason' => 'bad_quantity']);
        }

        $item = MenuItem::query()
            ->with(['optionGroups.options', 'sharedOptionGroups.options'])
            ->find($productId);

        if ($item === null || ! $item->is_available) {
            throw new WaiterWireException('REFUSED', 422, ['reason' => $item === null ? 'unknown_product' : 'unavailable']);
        }

        $item->withAutoOptionGroups(OptionGroup::autoApplied()->with(['options', 'categories:id'])->get());
        $this->checkSelection($item, $optionIds);

        foreach ($lines as &$line) {
            if ($line['menu_item_id'] === $productId && $line['option_ids'] === $optionIds && ($line['note'] ?? null) === $note) {
                $line['qty'] = min(self::MAX_QTY, $line['qty'] + $qty);

                return;
            }
        }
        unset($line);

        $lines[] = [
            'key' => 'd'.Str::lower(Str::random(8)),
            'menu_item_id' => $productId,
            'option_ids' => $optionIds,
            'qty' => $qty,
            'note' => $note,
        ];
    }

    /** Required groups need a choice and no group may exceed its maximum. @param list<int> $optionIds */
    private function checkSelection(MenuItem $item, array $optionIds): void
    {
        foreach ($item->orderedOptionGroups() as $group) {
            $picked = $group->options->whereIn('id', $optionIds);

            if ($group->is_required && $picked->isEmpty()) {
                throw new WaiterWireException('REFUSED', 422, ['reason' => 'required_option']);
            }

            $max = (int) ($group->max_select ?: ($group->is_variant ? 1 : max(1, $group->options->count())));
            if ($picked->count() > $max) {
                throw new WaiterWireException('REFUSED', 422, ['reason' => 'too_many_options']);
            }

            if ($picked->contains(fn ($o) => ! $o->is_available)) {
                throw new WaiterWireException('REFUSED', 422, ['reason' => 'unavailable']);
            }
        }
    }

    /** @param list<array<string,mixed>> $lines */
    private function opQty(array &$lines, array $op): void
    {
        $i = $this->draftIndex($lines, (string) ($op['line'] ?? ''));
        $qty = $lines[$i]['qty'] + (int) ($op['delta'] ?? 0);

        if ($qty > self::MAX_QTY) {
            throw new WaiterWireException('REFUSED', 422, ['reason' => 'bad_quantity']);
        }

        if ($qty <= 0) {
            array_splice($lines, $i, 1);

            return;
        }

        $lines[$i]['qty'] = $qty;
    }

    /** @param list<array<string,mixed>> $lines */
    private function opRemove(array &$lines, array $op): void
    {
        array_splice($lines, $this->draftIndex($lines, (string) ($op['line'] ?? '')), 1);
    }

    /** @param list<array<string,mixed>> $lines */
    private function opNote(array &$lines, array $op): void
    {
        $i = $this->draftIndex($lines, (string) ($op['line'] ?? ''));
        $note = is_string($op['note'] ?? null) ? trim($op['note']) : '';
        $lines[$i]['note'] = $note === '' ? null : mb_substr($note, 0, 200);
    }

    /**
     * Only an unsent (draft) line can be edited from the handheld; a sent line
     * is the till's and the kitchen's (voids are not offered here).
     *
     * @param  list<array<string,mixed>>  $lines
     */
    private function draftIndex(array $lines, string $key): int
    {
        foreach ($lines as $i => $line) {
            if ($line['key'] === $key) {
                return $i;
            }
        }

        throw new WaiterWireException(
            str_starts_with($key, 's') ? 'REFUSED' : 'NOT_FOUND',
            str_starts_with($key, 's') ? 422 : 404,
            str_starts_with($key, 's') ? ['reason' => 'line_sent'] : [],
        );
    }

    /** @param list<array<string,mixed>> $lines */
    private function persistDraft(TableCheckDraft $draft, TableVisit $visit, Restaurant $restaurant, array $lines, ?int $guests): void
    {
        $draft->forceFill([
            'restaurant_id' => $restaurant->id,
            'table_visit_id' => $visit->id,
            'lines' => array_values($lines),
            'guests' => $guests,
        ])->save();
    }

    /** Price the draft now, so an option the menu no longer allows refuses the whole batch. @param list<array<string,mixed>> $lines */
    private function priceOrRefuse(Restaurant $restaurant, DiningTable $table, TableVisit $visit, array $lines): void
    {
        $this->priced($restaurant, $table, $this->currentOrder($visit), $lines);
    }

    // ----------------------------------------------------------------- send

    /** @param list<array<string,mixed>> $lines */
    private function sendRound(Restaurant $restaurant, User $user, DiningTable $table, TableVisit $visit, array $lines): Order
    {
        if ($lines === []) {
            throw new WaiterWireException('REFUSED', 422, ['reason' => 'nothing_to_send']);
        }

        $exp = 10 ** $restaurant->currency->exponent();
        $order = $this->currentOrder($visit, lock: true);
        $priced = $this->priced($restaurant, $table, $order, $lines);
        $sentCount = $this->sentEngineLines($order)['count'];

        $newLines = array_slice($priced['lines'], $sentCount);
        $totals = $priced['totals'];

        if ($order === null) {
            $order = new Order([
                'status' => OrderStatus::NEW->value,
                'items' => [],
                'total' => 0,
                'currency' => $restaurant->currency->value,
                'order_type' => 'dine_in',
                'source' => 'waiter',
                'branch_id' => $table->branch_id,
                'dining_area_id' => $table->dining_area_id,
                'table_id' => $table->id,
                'table_visit_id' => $visit->id,
            ]);
            $order->restaurant_id = $restaurant->id;
            $order->forceFill(['acting_user_id' => $user->id]);
        }

        $order->forceFill([
            'items' => array_merge($order->items ?? [], array_map(fn ($l) => [
                'name' => $l['name'],
                'name_ar' => $l['name_ar'],
                'name_en' => $l['name_en'],
                'qty' => $l['quantity'],
                'options' => $l['options'],
                'note' => $l['note'],
                'line_total' => $l['line_total_minor'] / $exp,
            ], $newLines)),
            'total' => min($totals['total_minor'] / $exp, 99999999.99),
            'subtotal_minor' => $totals['subtotal_minor'],
            'discount_minor' => $totals['discount_minor'],
            'tax_minor' => $totals['tax_minor'],
            'charges_minor' => $totals['charges_minor'],
            'total_minor' => $totals['total_minor'],
        ])->save();

        $round = new OrderRound([
            'order_id' => $order->id,
            'sequence' => (int) OrderRound::withoutGlobalScopes()->where('order_id', $order->id)->max('sequence') + 1,
            'total' => array_sum(array_column($newLines, 'line_total_minor')) / $exp,
            'submitted_at' => now(),
        ]);
        $round->restaurant_id = $restaurant->id;
        $round->save();

        foreach ($newLines as $line) {
            $item = new OrderItem([
                'order_id' => $order->id,
                'order_round_id' => $round->id,
                'name' => $line['name'],
                'name_ar' => $line['name_ar'],
                'name_en' => $line['name_en'],
                'quantity' => $line['quantity'],
                'options' => $line['options'],
                'note' => $line['note'],
                'unit_price' => $line['unit_price_minor'] / $exp,
                'line_total' => $line['line_total_minor'] / $exp,
            ]);
            $item->restaurant_id = $restaurant->id;
            $item->forceFill([
                'menu_item_id' => $line['menu_item_id'],
                'unit_price_minor' => $line['unit_price_minor'],
                'line_total_minor' => $line['line_total_minor'],
                'price_source' => $line['price_source'],
            ])->save();
        }

        return $order;
    }

    private function notifyKitchen(Restaurant $restaurant, Order $order): void
    {
        $lang = $restaurant->default_language->value;
        $title = __('xorder.messages.push_new_order_title', [], $lang);
        $body = __('xorder.messages.push_new_order_body', [
            'code' => $order->code(),
            'total' => $order->total,
            'currency' => $order->currency,
        ], $lang);

        // Best-effort and after the response, exactly as the QR order does.
        app()->terminating(function () use ($restaurant, $order, $title, $body) {
            try {
                app(NotificationService::class)->toRestaurant(
                    $restaurant->id, 'order.created', $title, $body, ['order_id' => (string) $order->id], '/admin/orders',
                );
            } catch (\Throwable $e) {
                report($e);
            }
        });
    }

    // ---------------------------------------------------------- the check

    private function openVisit(DiningTable $table): ?TableVisit
    {
        $visit = TableVisit::query()
            ->where('table_id', $table->id)
            ->where('status', TableVisitStatus::OPEN->value)
            ->latest('id')
            ->first();

        // The same time-to-live TableVisitService applies when a scan or an op
        // arrives: an old visit is as good as closed.
        if ($visit !== null
            && $visit->opened_at->lte(now()->subMinutes((int) config('platform.table_session_ttl_minutes', 240)))) {
            return null;
        }

        return $visit;
    }

    private function currentOrder(?TableVisit $visit, bool $lock = false): ?Order
    {
        if ($visit === null) {
            return null;
        }

        $q = Order::query()
            ->where('table_visit_id', $visit->id)
            ->where('status', OrderStatus::NEW->value)
            ->with('rounds.items')
            ->orderBy('id');

        return ($lock ? $q->lockForUpdate() : $q)->first();
    }

    /** @return array<string,mixed> */
    private function build(Restaurant $restaurant, DiningTable $table, ?TableVisit $visit): array
    {
        $exp = 10 ** $restaurant->currency->exponent();
        $order = $this->currentOrder($visit);
        $draft = $visit === null ? null : TableCheckDraft::query()->where('table_visit_id', $visit->id)->first();
        $draftLines = $draft?->lines ?? [];

        $out = [];
        $totals = ['subtotal_minor' => 0, 'discount_minor' => 0, 'tax_minor' => 0, 'charges_minor' => 0, 'total_minor' => 0];

        if ($order !== null || $draftLines !== []) {
            $priced = $this->priced($restaurant, $table, $order, $draftLines);
            $totals = $priced['totals'];
            $sent = $this->sentEngineLines($order);

            foreach ($sent['rows'] as $i => $row) {
                $out[] = [
                    'key' => 's'.$row['item']->id,
                    'product_id' => $row['item']->menu_item_id === null ? null : (int) $row['item']->menu_item_id,
                    'name' => ['en' => (string) ($row['item']->name_en ?: $row['item']->name), 'ar' => $row['item']->name_ar],
                    'qty' => (int) $row['item']->quantity,
                    'total_minor' => $priced['lines'][$i]['line_total_minor'],
                    'modifiers' => array_map(fn ($o) => ['en' => (string) $o], (array) ($row['item']->options ?? [])),
                    'stage' => 'sent',
                    'round' => $row['round'],
                ] + ($row['item']->note ? ['note' => $row['item']->note] : []);
            }

            foreach ($draftLines as $j => $line) {
                $p = $priced['lines'][$sent['count'] + $j];
                $out[] = [
                    'key' => $line['key'],
                    'product_id' => (int) $line['menu_item_id'],
                    'name' => ['en' => (string) ($p['name_en'] ?: $p['name']), 'ar' => $p['name_ar']],
                    'qty' => $line['qty'],
                    'total_minor' => $p['line_total_minor'],
                    'modifiers' => array_map(fn ($o) => ['en' => (string) $o], $p['options']),
                    'stage' => 'draft',
                ] + ($line['note'] ? ['note' => $line['note']] : []);
            }
        }

        return [
            'table_id' => $table->id,
            'table_label' => (string) $table->label,
            'currency' => ['code' => $restaurant->currency->value, 'exponent' => $restaurant->currency->exponent()],
            'version' => (int) ($visit?->check_version ?? 0),
            'lines' => $out,
            'subtotal_minor' => $totals['subtotal_minor'],
            'service_minor' => $totals['charges_minor'],
            'tax_minor' => $totals['tax_minor'],
            'discount_minor' => $totals['discount_minor'],
            'total_minor' => $totals['total_minor'],
            'rounds_sent' => (int) ($order?->rounds->max('sequence') ?? 0),
        ] + ($draft?->guests !== null ? ['guests' => $draft->guests] : []);
    }

    /**
     * Sent lines first (frozen at the price they were sent at), then the draft
     * priced from the menu. A draft line never carries a price of its own.
     *
     * @param  list<array<string,mixed>>  $draftLines
     * @return array{lines: list<array<string,mixed>>, totals: array<string,int>}
     */
    private function priced(Restaurant $restaurant, DiningTable $table, ?Order $order, array $draftLines): array
    {
        $exp = 10 ** $restaurant->currency->exponent();
        $branch = Branch::query()->findOrFail($table->branch_id);

        $engine = [];
        foreach ($this->sentEngineLines($order)['rows'] as $row) {
            $item = $row['item'];
            $unit = $item->unit_price_minor ?? (int) round((float) $item->unit_price * $exp);
            $engine[] = [
                'menu_item_id' => $item->menu_item_id,
                'quantity' => (int) $item->quantity,
                'unit_price_minor' => $unit,
                'name_snapshot' => $item->name,
                'price_override' => ['unit_price_minor' => $unit],
                'note' => $item->note,
            ];
        }

        foreach ($draftLines as $line) {
            $engine[] = [
                'menu_item_id' => $line['menu_item_id'],
                'quantity' => $line['qty'],
                'option_ids' => $line['option_ids'],
                'note' => $line['note'] ?? null,
                'client_line_id' => $line['key'],
            ];
        }

        if ($engine === []) {
            return ['lines' => [], 'totals' => ['subtotal_minor' => 0, 'discount_minor' => 0, 'tax_minor' => 0, 'charges_minor' => 0, 'total_minor' => 0]];
        }

        return $this->pricing->price($branch, 'dine_in', $engine, 0, $restaurant->currency);
    }

    /** @return array{count: int, rows: list<array{item: OrderItem, round: int}>} */
    private function sentEngineLines(?Order $order): array
    {
        $rows = [];

        foreach ($order?->rounds->sortBy('sequence') ?? [] as $round) {
            foreach ($round->items->sortBy('id') as $item) {
                $rows[] = ['item' => $item, 'round' => (int) $round->sequence];
            }
        }

        return ['count' => count($rows), 'rows' => $rows];
    }
}
