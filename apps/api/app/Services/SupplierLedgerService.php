<?php

namespace App\Services;

use App\Enums\InvoiceVoidReason;
use App\Enums\PaymentVoidReason;
use App\Enums\PurchaseStatus;
use App\Enums\SupplierPaymentMethod;
use App\Exceptions\PurchasingRefusal;
use App\Models\PosCashMovement;
use App\Models\PurchaseOrder;
use App\Models\Supplier;
use App\Models\SupplierInvoice;
use App\Models\SupplierInvoiceLine;
use App\Models\SupplierPayment;
use App\Models\SupplierPaymentAllocation;
use App\Models\User;
use App\Support\StockCosting;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice c: every write to supplier invoices and payments. The
 * platform's version of the till's migration-30/33 triggers, as one service
 * with row locks (design D10: no DB triggers, because the platform runs SQLite
 * and PostgreSQL with the same code).
 *
 *   invoice  create; edit only while live and nothing is allocated to it;
 *            void (reason code) only while nothing live is allocated to it
 *   payment  record, allocated to zero or more invoices of the same
 *            supplier and branch, the rest on account; never edited; void
 *            (reason code) gives the room it took back
 *
 * THE RULE: an invoice's live allocations never exceed its total. pay()
 * locks every invoice it touches (FOR UPDATE, ascending id, so two payments
 * can't deadlock), then SUMs the live allocations under that lock, then
 * writes. Two bookkeepers paying the same invoice at once queue on the row
 * instead of both reading the same stale total. On SQLite lockForUpdate is a
 * no-op but SQLite has one writer at a time, so the check-then-write stays
 * serial; PostgreSQL gets the real row lock (proved by hand, design §15).
 *
 * The same lock serialises the other two cross-row rules: an invoice can't be
 * voided or edited while money is allocated to it, and a payment can't land
 * on an invoice being voided. Every refusal is a PurchasingRefusal thrown
 * inside the transaction, so nothing of a refused write survives.
 *
 * An invoice NEVER touches stock or cost: nothing here reads or writes the
 * stock ledger (till supplier_invoice.dart, design §10 C4).
 */
class SupplierLedgerService
{
    public function __construct(private SupplierAccountService $accounts) {}

    // ============================================================= invoices

    /** @param array<string,mixed> $data validated StoreSupplierInvoiceRequest */
    public function createInvoice(array $data, User $by): SupplierInvoice
    {
        return $this->guardNumber((string) $data['number'], fn () => DB::transaction(function () use ($data, $by) {
            $restaurant = $by->restaurant;

            $invoice = new SupplierInvoice;
            $invoice->forceFill([
                'restaurant_id' => $by->restaurant_id,
                'currency' => $restaurant->currency?->value ?? 'EGP',
                'exponent' => $restaurant->currency?->exponent() ?? 2,
                'created_by' => $by->id,
            ]);
            $lines = $this->fillInvoice($invoice, $data, $by);
            $invoice->save();
            $this->writeLines($invoice, $lines);

            AuditLogger::record('supplier_invoice.created', [
                'auditable' => $invoice,
                'description' => sprintf('Supplier invoice "%s" from "%s" entered', $invoice->number, $invoice->supplier_name),
                'properties' => $this->invoiceFacts($invoice, count($lines)),
            ]);

            return $invoice;
        }));
    }

    /** Rewrite a live, unpaid invoice (header and lines, wholesale). */
    public function updateInvoice(SupplierInvoice $invoice, array $data, User $by): SupplierInvoice
    {
        return $this->guardNumber((string) $data['number'], fn () => DB::transaction(function () use ($invoice, $data, $by) {
            $locked = $this->lockInvoice($invoice);

            if ($locked->isVoided()) {
                throw PurchasingRefusal::conflict('INVOICE_VOIDED', 'invoice_voided');
            }
            $paid = $this->accounts->allocatedByInvoice($locked->restaurant_id, [$locked->id])[$locked->id] ?? 0;
            if ($paid > 0) {
                // Its figures are what the payments were checked against:
                // void the payments, or void this and enter it again.
                throw PurchasingRefusal::conflict('INVOICE_HAS_PAYMENTS', 'invoice_locked_paid', ['paid' => $this->money($paid, $locked)]);
            }

            $lines = $this->fillInvoice($locked, $data, $by);
            $locked->save();
            SupplierInvoiceLine::withoutGlobalScopes()->where('supplier_invoice_id', $locked->id)->delete();
            $this->writeLines($locked, $lines);

            AuditLogger::record('supplier_invoice.updated', [
                'auditable' => $locked,
                'description' => sprintf('Supplier invoice "%s" from "%s" updated', $locked->number, $locked->supplier_name),
                'properties' => $this->invoiceFacts($locked, count($lines)),
            ]);

            return $locked;
        }));
    }

    public function voidInvoice(SupplierInvoice $invoice, InvoiceVoidReason $reason, ?string $note, User $by): SupplierInvoice
    {
        return DB::transaction(function () use ($invoice, $reason, $note, $by) {
            $locked = $this->lockInvoice($invoice);

            if ($locked->isVoided()) {
                throw PurchasingRefusal::conflict('INVOICE_ALREADY_VOIDED', 'invoice_already_voided');
            }
            // Under the invoice lock, so a payment can't land between this
            // check and the void (pay() takes the same lock first).
            $paid = $this->accounts->allocatedByInvoice($locked->restaurant_id, [$locked->id])[$locked->id] ?? 0;
            if ($paid > 0) {
                throw PurchasingRefusal::conflict('INVOICE_HAS_PAYMENTS', 'invoice_has_payments', ['paid' => $this->money($paid, $locked)], null, ['paid_minor' => $paid]);
            }

            $locked->forceFill([
                'voided_at' => now(),
                'voided_by' => $by->id,
                'void_reason' => $reason,
                'void_note' => $note,
                // The number is free again: a genuine re-entry after a void
                // is the reason the void exists.
                'active_number_key' => null,
                'updated_by' => $by->id,
            ])->save();

            AuditLogger::record('supplier_invoice.voided', [
                'auditable' => $locked,
                'description' => sprintf('Supplier invoice "%s" from "%s" voided (%s)', $locked->number, $locked->supplier_name, $reason->value),
                'properties' => ['reason' => $reason->value, 'note' => $note, 'total_minor' => $locked->total_minor],
            ]);

            return $locked;
        });
    }

    // ============================================================= payments

    /** @param array<string,mixed> $data validated StoreSupplierPaymentRequest */
    public function pay(array $data, User $by): SupplierPayment
    {
        try {
            return DB::transaction(fn () => $this->writePayment($data, $by));
        } catch (UniqueConstraintViolationException) {
            // Only drawer_link_key can collide here (allocations are
            // distinct per payment by validation): somebody linked the same
            // pay-out a moment before us.
            throw PurchasingRefusal::conflict('DRAWER_ALREADY_LINKED', 'drawer_already_linked', [], 'pos_cash_movement_id');
        }
    }

    public function voidPayment(SupplierPayment $payment, PaymentVoidReason $reason, ?string $note, User $by): SupplierPayment
    {
        return DB::transaction(function () use ($payment, $reason, $note, $by) {
            $locked = SupplierPayment::withoutGlobalScopes()
                ->where('restaurant_id', $payment->restaurant_id)
                ->whereKey($payment->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($locked->isVoided()) {
                throw PurchasingRefusal::conflict('PAYMENT_ALREADY_VOIDED', 'payment_already_voided');
            }

            $locked->forceFill([
                'voided_at' => now(),
                'voided_by' => $by->id,
                'void_reason' => $reason,
                'void_note' => $note,
                // The pay-out may be linked to a corrected payment. The id
                // itself stays on this row, as history.
                'drawer_link_key' => null,
            ])->save();

            AuditLogger::record('supplier_payment.voided', [
                'auditable' => $locked,
                'description' => sprintf('Payment #%d of %s to "%s" voided (%s)', $locked->id, $this->money($locked->amount_minor, $locked), $locked->supplier_name, $reason->value),
                'properties' => [
                    'reason' => $reason->value,
                    'note' => $note,
                    'amount_minor' => $locked->amount_minor,
                    'allocations' => $locked->allocations()->get(['supplier_invoice_id', 'amount_minor'])->toArray(),
                ],
            ]);

            return $locked;
        });
    }

    // ============================================================ internals

    private function writePayment(array $data, User $by): SupplierPayment
    {
        $restaurant = $by->restaurant;
        $currency = $restaurant->currency?->value ?? 'EGP';
        $exponent = $restaurant->currency?->exponent() ?? 2;
        $supplier = Supplier::query()->findOrFail($data['supplier_id']);
        $branchId = (int) $data['branch_id'];
        $amount = (int) $data['amount_minor'];
        $method = SupplierPaymentMethod::from($data['method']);

        /** @var list<array{index:int, invoice_id:int, amount:int}> $asked */
        $asked = [];
        foreach (array_values($data['allocations'] ?? []) as $i => $a) {
            $asked[] = ['index' => $i, 'invoice_id' => (int) $a['supplier_invoice_id'], 'amount' => (int) $a['amount_minor']];
        }
        if (array_sum(array_column($asked, 'amount')) > $amount) {
            throw PurchasingRefusal::invalid('ALLOCATIONS_EXCEED_PAYMENT', 'allocations_exceed_payment', [], 'allocations');
        }

        // Lock every invoice this payment touches, in ascending id order, and
        // only then read what is already allocated to them.
        $ids = array_values(array_unique(array_column($asked, 'invoice_id')));
        sort($ids);
        $invoices = SupplierInvoice::withoutGlobalScopes()
            ->where('restaurant_id', $by->restaurant_id)
            ->whereIn('id', $ids)
            ->orderBy('id')
            ->lockForUpdate()
            ->get()
            ->keyBy('id');
        if ($invoices->count() !== count($ids)) {
            throw PurchasingRefusal::invalid('PAYMENT_INVOICE_UNKNOWN', 'payment_invoice_unknown', [], 'allocations');
        }
        $allocated = $this->accounts->allocatedByInvoice($by->restaurant_id, $ids);

        foreach ($asked as $a) {
            $invoice = $invoices->get($a['invoice_id']);
            $field = "allocations.{$a['index']}.supplier_invoice_id";
            $replace = ['number' => $invoice->number];

            if ($invoice->supplier_id !== $supplier->id) {
                throw PurchasingRefusal::invalid('PAYMENT_OTHER_SUPPLIER', 'payment_other_supplier', $replace, $field);
            }
            if ($invoice->branch_id !== $branchId) {
                throw PurchasingRefusal::invalid('PAYMENT_OTHER_BRANCH', 'payment_other_branch', $replace, $field);
            }
            if ($invoice->isVoided()) {
                throw PurchasingRefusal::conflict('PAYMENT_INVOICE_VOIDED', 'payment_invoice_voided', $replace, $field);
            }
            if ($invoice->currency !== $currency) {
                throw PurchasingRefusal::invalid('CURRENCY_DIFFERS', 'currency_differs', $replace + ['invoice' => $invoice->currency, 'payment' => $currency], $field);
            }

            $paid = $allocated[$invoice->id] ?? 0;
            $room = max(0, $invoice->total_minor - $paid);
            if ($a['amount'] > $room) {
                throw PurchasingRefusal::conflict('PAYMENT_EXCEEDS_INVOICE', 'payment_exceeds_invoice', $replace + [
                    'total' => $this->money($invoice->total_minor, $invoice),
                    'paid' => $this->money($paid, $invoice),
                    'room' => $this->money($room, $invoice),
                ], "allocations.{$a['index']}.amount_minor", [
                    'supplier_invoice_id' => $invoice->id,
                    'total_minor' => $invoice->total_minor,
                    'paid_minor' => $paid,
                    'room_minor' => $room,
                ]);
            }
        }

        $movementId = $this->checkDrawerLink($data['pos_cash_movement_id'] ?? null, $method, $branchId, $amount, $by, $currency, $exponent);

        $payment = new SupplierPayment;
        $payment->forceFill([
            'restaurant_id' => $by->restaurant_id,
            'branch_id' => $branchId,
            'supplier_id' => $supplier->id,
            'supplier_name' => $this->nameOf($supplier, $by),
            'method' => $method,
            'amount_minor' => $amount,
            'currency' => $currency,
            'exponent' => $exponent,
            'reference' => $data['reference'] ?? null,
            'paid_at' => $data['paid_at'],
            'note' => $data['note'] ?? null,
            'pos_cash_movement_id' => $movementId,
            'drawer_link_key' => $movementId,
            'created_by' => $by->id,
        ])->save();

        foreach ($asked as $a) {
            $row = new SupplierPaymentAllocation;
            $row->forceFill([
                'restaurant_id' => $by->restaurant_id,
                'supplier_payment_id' => $payment->id,
                'supplier_invoice_id' => $a['invoice_id'],
                'amount_minor' => $a['amount'],
            ])->save();
        }

        $allocatedTotal = array_sum(array_column($asked, 'amount'));
        AuditLogger::record('supplier_payment.recorded', [
            'auditable' => $payment,
            'description' => sprintf('Payment of %s to "%s" recorded', $this->money($amount, $payment), $payment->supplier_name),
            'properties' => [
                'amount_minor' => $amount,
                'method' => $method->value,
                'allocations' => array_map(fn ($a) => ['supplier_invoice_id' => $a['invoice_id'], 'amount_minor' => $a['amount']], $asked),
                'on_account_minor' => $amount - $allocatedTotal,
                'pos_cash_movement_id' => $movementId,
            ],
        ]);

        return $payment;
    }

    /**
     * Design D13, the till's migration-33 rules: the pay-out must be this
     * business's, money OUT of a drawer at this branch, for EXACTLY the
     * payment's amount, and not already linked to a live payment. Only a
     * cash payment comes out of a drawer. The movement row is locked so two
     * payments can't both claim it (the unique drawer_link_key backs this).
     */
    private function checkDrawerLink(mixed $movementId, SupplierPaymentMethod $method, int $branchId, int $amount, User $by, string $currency, int $exponent): ?int
    {
        if ($movementId === null || $movementId === '') {
            return null;
        }
        $field = 'pos_cash_movement_id';

        if ($method !== SupplierPaymentMethod::CASH) {
            throw PurchasingRefusal::invalid('DRAWER_NEEDS_CASH', 'drawer_needs_cash', [], $field);
        }

        $movement = PosCashMovement::withoutGlobalScopes()
            ->where('restaurant_id', $by->restaurant_id)
            ->whereKey((int) $movementId)
            ->lockForUpdate()
            ->first();
        if ($movement === null) {
            throw PurchasingRefusal::invalid('DRAWER_UNKNOWN', 'drawer_unknown', [], $field);
        }
        if ($movement->direction !== 'out') {
            throw PurchasingRefusal::invalid('DRAWER_NOT_PAY_OUT', 'drawer_not_pay_out', [], $field);
        }
        if ((int) $movement->branch_id !== $branchId) {
            throw PurchasingRefusal::invalid('DRAWER_OTHER_BRANCH', 'drawer_other_branch', [], $field);
        }
        if ((int) $movement->amount_minor !== $amount) {
            throw PurchasingRefusal::invalid('DRAWER_AMOUNT_DIFFERS', 'drawer_amount_differs', [
                'moved' => self::formatMinor((int) $movement->amount_minor, $exponent, $currency),
            ], $field);
        }
        if (SupplierPayment::withoutGlobalScopes()->where('drawer_link_key', $movement->id)->exists()) {
            throw PurchasingRefusal::conflict('DRAWER_ALREADY_LINKED', 'drawer_already_linked', [], $field);
        }

        return $movement->id;
    }

    /**
     * Put a request onto an invoice (new or locked), after checking what
     * depends on other rows. Returns the normalised lines to write.
     *
     * @return list<array{description:string, quantity_milli:int, unit_cost_minor:int, tax_rate_bp:int}>
     */
    private function fillInvoice(SupplierInvoice $invoice, array $data, User $by): array
    {
        $supplier = Supplier::query()->findOrFail($data['supplier_id']);
        $branchId = (int) $data['branch_id'];

        $order = null;
        if (! empty($data['purchase_order_id'])) {
            $order = PurchaseOrder::query()->findOrFail($data['purchase_order_id']);
            if ($order->supplier_id !== $supplier->id) {
                throw PurchasingRefusal::invalid('INVOICE_PO_OTHER_SUPPLIER', 'invoice_po_other_supplier', [], 'purchase_order_id');
            }
            if ($order->branch_id !== $branchId) {
                throw PurchasingRefusal::invalid('INVOICE_PO_OTHER_BRANCH', 'invoice_po_other_branch', [], 'purchase_order_id');
            }
            if ($order->status === PurchaseStatus::DRAFT) {
                // A draft was never sent: nothing was asked of the supplier.
                throw PurchasingRefusal::invalid('INVOICE_PO_DRAFT', 'invoice_po_draft', [], 'purchase_order_id');
            }
        }

        $number = trim((string) $data['number']);
        $key = SupplierInvoice::numberKey($number);
        $taken = SupplierInvoice::query()
            ->where('supplier_id', $supplier->id)
            ->where('active_number_key', $key)
            ->when($invoice->exists, fn ($q) => $q->whereKeyNot($invoice->id))
            ->exists();
        if ($taken) {
            throw PurchasingRefusal::invalid('INVOICE_NUMBER_TAKEN', 'invoice_number_taken', ['number' => $number], 'number');
        }

        $lines = [];
        foreach (array_values($data['lines'] ?? []) as $l) {
            $lines[] = [
                'description' => mb_substr(trim((string) $l['description']), 0, 200),
                'quantity_milli' => (int) $l['quantity_milli'],
                'unit_cost_minor' => (int) $l['unit_cost_minor'],
                'tax_rate_bp' => (int) ($l['tax_rate_bp'] ?? 0),
            ];
        }

        if ($lines !== []) {
            // From the lines, with the till's rounding points: costAt per
            // line, tax rounded once PER RATE. Never typed.
            $totals = PurchaseOrderService::totals(array_map(fn ($l) => [
                'ordered_milli' => $l['quantity_milli'], 'unit_cost_minor' => $l['unit_cost_minor'], 'tax_rate_bp' => $l['tax_rate_bp'],
            ], $lines));
            $total = $totals['total_minor'];
            $tax = $totals['tax_minor'];
            $field = 'lines';
        } else {
            // Typed off the paper: the total, and the tax as a figure or as
            // the rate INSIDE the total (the till's taxWithinBp).
            $total = (int) $data['total_minor'];
            $tax = isset($data['tax_minor'])
                ? (int) $data['tax_minor']
                : (isset($data['tax_rate_bp']) ? StockCosting::taxWithinBp($total, (int) $data['tax_rate_bp']) : 0);
            $field = 'total_minor';
        }

        if ($total <= 0) {
            throw PurchasingRefusal::invalid('INVOICE_TOTAL_NOT_POSITIVE', 'invoice_total_not_positive', [], $field);
        }
        if ($tax < 0 || $tax > $total) {
            throw PurchasingRefusal::invalid('INVOICE_TAX_EXCEEDS_TOTAL', 'invoice_tax_exceeds_total', [], 'tax_minor');
        }

        $issued = Carbon::parse($data['issued_at'])->startOfDay();
        // The supplier's terms as they stand now, stored: a later change to
        // the terms must not move this invoice's due date.
        $due = ! empty($data['due_at'])
            ? Carbon::parse($data['due_at'])->startOfDay()
            : $issued->copy()->addDays((int) $supplier->payment_term_days);

        $invoice->forceFill([
            'branch_id' => $branchId,
            'supplier_id' => $supplier->id,
            'supplier_name' => $supplier->id === $invoice->supplier_id && $invoice->supplier_name
                ? $invoice->supplier_name
                : $this->nameOf($supplier, $by),
            'purchase_order_id' => $order?->id,
            'purchase_order_reference' => $order?->reference,
            'number' => mb_substr($number, 0, 64),
            'active_number_key' => $key,
            'total_minor' => $total,
            'tax_minor' => $tax,
            'issued_at' => $issued->format('Y-m-d'),
            'due_at' => $due->format('Y-m-d'),
            'note' => $data['note'] ?? null,
            'updated_by' => $by->id,
        ]);

        return $lines;
    }

    /** @param list<array{description:string, quantity_milli:int, unit_cost_minor:int, tax_rate_bp:int}> $lines */
    private function writeLines(SupplierInvoice $invoice, array $lines): void
    {
        foreach ($lines as $i => $l) {
            $row = new SupplierInvoiceLine;
            $row->forceFill($l + [
                'restaurant_id' => $invoice->restaurant_id,
                'supplier_invoice_id' => $invoice->id,
                'sort_order' => $i,
            ])->save();
        }
    }

    private function lockInvoice(SupplierInvoice $invoice): SupplierInvoice
    {
        return SupplierInvoice::withoutGlobalScopes()
            ->where('restaurant_id', $invoice->restaurant_id)
            ->whereKey($invoice->id)
            ->lockForUpdate()
            ->firstOrFail();
    }

    /** A duplicate live number that slipped past the pre-check is still a 422, never a 500. */
    private function guardNumber(string $number, callable $write): mixed
    {
        try {
            return $write();
        } catch (UniqueConstraintViolationException) {
            throw PurchasingRefusal::invalid('INVOICE_NUMBER_TAKEN', 'invoice_number_taken', ['number' => trim($number)], 'number');
        }
    }

    private function invoiceFacts(SupplierInvoice $invoice, int $lines): array
    {
        return [
            'supplier_id' => $invoice->supplier_id,
            'branch_id' => $invoice->branch_id,
            'purchase_order_id' => $invoice->purchase_order_id,
            'total_minor' => $invoice->total_minor,
            'tax_minor' => $invoice->tax_minor,
            'currency' => $invoice->currency,
            'lines' => $lines,
        ];
    }

    /** Whichever name is set, the business's default language first. */
    private function nameOf(Supplier $supplier, User $by): string
    {
        $lang = $by->restaurant?->default_language;
        $lang = $lang instanceof \BackedEnum ? $lang->value : (string) ($lang ?: 'en');
        $first = $lang === 'ar' ? $supplier->name_ar : $supplier->name_en;
        $second = $lang === 'ar' ? $supplier->name_en : $supplier->name_ar;

        return mb_substr((string) ($first ?: $second), 0, 160);
    }

    private function money(int $minor, SupplierInvoice|SupplierPayment $doc): string
    {
        return self::formatMinor($minor, (int) $doc->exponent, (string) $doc->currency);
    }

    /** 60000, 2, EGP → "600.00 EGP". Digits only, never a float. */
    public static function formatMinor(int $minor, int $exponent, string $currency): string
    {
        $abs = abs($minor);
        $scale = 10 ** $exponent;
        $text = intdiv($abs, $scale).($exponent > 0 ? '.'.str_pad((string) ($abs % $scale), $exponent, '0', STR_PAD_LEFT) : '');

        return ($minor < 0 ? '-' : '').$text.' '.$currency;
    }
}
