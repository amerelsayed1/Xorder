<?php

namespace App\Services;

use App\Models\Supplier;
use App\Models\SupplierInvoice;
use App\Models\SupplierPayment;
use App\Models\SupplierPaymentAllocation;
use App\Support\SupplierAccount;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice c: supplier balances, DERIVED, never stored.
 *
 * Loads rows and hands them to App\Support\SupplierAccount, which does the
 * arithmetic (the till's, generalised to many allocations per payment). No
 * column anywhere holds a balance, a paid amount or an outstanding amount.
 *
 * Portable SQL only: SUM, COALESCE and a join, cast to int in PHP.
 */
class SupplierAccountService
{
    /**
     * What the LIVE payments have allocated to each invoice. Allocations of a
     * voided payment don't count: voiding a payment gives its room back.
     *
     * @param  list<int>|null  $invoiceIds  null = every invoice of the tenant
     * @return array<int,int> invoice id => allocated minor
     */
    public function allocatedByInvoice(int $restaurantId, ?array $invoiceIds = null): array
    {
        if ($invoiceIds === []) {
            return [];
        }

        return DB::table('supplier_payment_allocations as spa')
            ->join('supplier_payments as sp', 'sp.id', '=', 'spa.supplier_payment_id')
            ->where('spa.restaurant_id', $restaurantId)
            ->whereNull('sp.voided_at')
            ->when($invoiceIds !== null, fn ($q) => $q->whereIn('spa.supplier_invoice_id', $invoiceIds))
            ->groupBy('spa.supplier_invoice_id')
            ->selectRaw('spa.supplier_invoice_id as invoice_id, COALESCE(SUM(spa.amount_minor), 0) as allocated')
            ->pluck('allocated', 'invoice_id')
            ->map(fn ($v) => (int) $v)
            ->all();
    }

    /**
     * How much of each payment is allocated (live or not: a voided payment is
     * excluded by the caller, never half-counted).
     *
     * @param  list<int>|null  $paymentIds
     * @return array<int,int> payment id => allocated minor
     */
    public function allocatedByPayment(int $restaurantId, ?array $paymentIds = null): array
    {
        if ($paymentIds === []) {
            return [];
        }

        return SupplierPaymentAllocation::withoutGlobalScopes()
            ->where('restaurant_id', $restaurantId)
            ->when($paymentIds !== null, fn ($q) => $q->whereIn('supplier_payment_id', $paymentIds))
            ->groupBy('supplier_payment_id')
            ->selectRaw('supplier_payment_id, COALESCE(SUM(amount_minor), 0) as allocated')
            ->pluck('allocated', 'supplier_payment_id')
            ->map(fn ($v) => (int) $v)
            ->all();
    }

    /**
     * One supplier's account: the figures, the statement with its running
     * balance, the open invoices, and every payment (voided ones flagged,
     * for the record; they are not in the statement or the figures).
     *
     * @return array<string,mixed>
     */
    public function account(Supplier $supplier, ?int $branchId, string $asOf): array
    {
        $rid = $supplier->restaurant_id;

        $invoices = SupplierInvoice::query()
            ->where('supplier_id', $supplier->id)
            ->when($branchId, fn ($q) => $q->where('branch_id', $branchId))
            ->orderBy('issued_at')->orderBy('id')
            ->get();
        $payments = SupplierPayment::query()
            ->with('allocations.invoice:id,number')
            ->where('supplier_id', $supplier->id)
            ->when($branchId, fn ($q) => $q->where('branch_id', $branchId))
            ->orderBy('paid_at')->orderBy('id')
            ->get();

        $byInvoice = $this->allocatedByInvoice($rid, $invoices->pluck('id')->all());
        $byPayment = $this->allocatedByPayment($rid, $payments->pluck('id')->all());

        $invoiceRows = $invoices->map(fn (SupplierInvoice $i) => [
            'id' => $i->id,
            'total_minor' => $i->total_minor,
            'due_at' => $i->due_at->format('Y-m-d'),
            'voided' => $i->isVoided(),
            'allocated_minor' => $byInvoice[$i->id] ?? 0,
        ])->all();
        $paymentRows = $payments->map(fn (SupplierPayment $p) => [
            'id' => $p->id,
            'amount_minor' => $p->amount_minor,
            'voided' => $p->isVoided(),
            'allocated_minor' => $byPayment[$p->id] ?? 0,
        ])->all();

        $figures = SupplierAccount::figures($invoiceRows, $paymentRows, $asOf);

        $statement = SupplierAccount::statement(
            $invoices->map(fn (SupplierInvoice $i) => [
                'id' => $i->id, 'date' => $i->issued_at->format('Y-m-d'), 'amount_minor' => $i->total_minor,
                'voided' => $i->isVoided(), 'number' => $i->number, 'branch_id' => $i->branch_id,
                'due_at' => $i->due_at->format('Y-m-d'), 'purchase_order_reference' => $i->purchase_order_reference,
            ])->all(),
            $payments->map(fn (SupplierPayment $p) => [
                'id' => $p->id, 'date' => $p->paid_at->format('Y-m-d'), 'amount_minor' => $p->amount_minor,
                'voided' => $p->isVoided(), 'method' => $p->method->value, 'reference' => $p->reference,
                'branch_id' => $p->branch_id,
            ])->all(),
        );

        $open = $invoices
            ->reject(fn (SupplierInvoice $i) => $i->isVoided() || SupplierAccount::isSettled($i->total_minor, $byInvoice[$i->id] ?? 0))
            ->map(function (SupplierInvoice $i) use ($byInvoice, $asOf) {
                $paid = $byInvoice[$i->id] ?? 0;
                $due = $i->due_at->format('Y-m-d');

                return [
                    'id' => $i->id,
                    'number' => $i->number,
                    'branch_id' => $i->branch_id,
                    'issued_at' => $i->issued_at->format('Y-m-d'),
                    'due_at' => $due,
                    'total_minor' => $i->total_minor,
                    'paid_minor' => $paid,
                    'outstanding_minor' => SupplierAccount::invoiceOutstanding($i->total_minor, $paid),
                    'is_overdue' => SupplierAccount::isOverdue($due, $asOf, false, $i->total_minor, $paid),
                    'days_late' => SupplierAccount::daysLate($due, $asOf, false, $i->total_minor, $paid),
                ];
            })->values()->all();

        $paymentList = $payments->sortByDesc(fn ($p) => [$p->paid_at->format('Y-m-d'), $p->id])->map(fn (SupplierPayment $p) => [
            'id' => $p->id,
            'branch_id' => $p->branch_id,
            'paid_at' => $p->paid_at->format('Y-m-d'),
            'method' => $p->method->value,
            'reference' => $p->reference,
            'amount_minor' => $p->amount_minor,
            'allocated_minor' => $byPayment[$p->id] ?? 0,
            'on_account_minor' => $p->amount_minor - ($byPayment[$p->id] ?? 0),
            'is_voided' => $p->isVoided(),
            'void_reason' => $p->void_reason?->value,
            'allocations' => $p->allocations->map(fn ($a) => [
                'supplier_invoice_id' => $a->supplier_invoice_id,
                'number' => $a->invoice?->number,
                'amount_minor' => $a->amount_minor,
            ])->values()->all(),
        ])->values()->all();

        return [
            'figures' => $figures,
            'statement' => $statement,
            'open_invoices' => $open,
            'payments' => $paymentList,
            'voided_invoices' => $invoices->filter(fn ($i) => $i->isVoided())->count(),
        ];
    }

    /**
     * Every supplier's figures in one pass, for the supplier list. Suppliers
     * with no invoice and no payment are left out (they owe and are owed
     * nothing). Keyed by supplier id.
     *
     * @return array<int, array<string,int>>
     */
    public function balances(int $restaurantId, ?int $branchId, string $asOf): array
    {
        $invoices = SupplierInvoice::query()
            ->when($branchId, fn ($q) => $q->where('branch_id', $branchId))
            ->get(['id', 'supplier_id', 'total_minor', 'due_at', 'voided_at']);
        $payments = SupplierPayment::query()
            ->when($branchId, fn ($q) => $q->where('branch_id', $branchId))
            ->get(['id', 'supplier_id', 'amount_minor', 'voided_at']);

        $byInvoice = $this->allocatedByInvoice($restaurantId, $branchId ? $invoices->pluck('id')->all() : null);
        $byPayment = $this->allocatedByPayment($restaurantId, $branchId ? $payments->pluck('id')->all() : null);

        $groups = [];
        foreach ($invoices as $i) {
            $groups[$i->supplier_id]['invoices'][] = [
                'id' => $i->id, 'total_minor' => $i->total_minor, 'due_at' => $i->due_at->format('Y-m-d'),
                'voided' => $i->isVoided(), 'allocated_minor' => $byInvoice[$i->id] ?? 0,
            ];
        }
        foreach ($payments as $p) {
            $groups[$p->supplier_id]['payments'][] = [
                'id' => $p->id, 'amount_minor' => $p->amount_minor,
                'voided' => $p->isVoided(), 'allocated_minor' => $byPayment[$p->id] ?? 0,
            ];
        }

        $out = [];
        foreach ($groups as $supplierId => $g) {
            $out[$supplierId] = SupplierAccount::figures($g['invoices'] ?? [], $g['payments'] ?? [], $asOf);
        }
        ksort($out);

        return $out;
    }
}
