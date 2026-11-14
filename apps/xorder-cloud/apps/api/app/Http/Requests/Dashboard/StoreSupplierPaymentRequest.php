<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\SupplierPaymentMethod;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice c: a supplier payment and its allocations.
 *
 * `allocations` may be empty (all of it on account) and is at most one row
 * per invoice. What depends on other rows (the room left on each invoice,
 * same supplier and branch, not voided, the drawer link's rules) is decided
 * by SupplierLedgerService under locks.
 *
 * A payment is never edited, so there is no update request: void it and
 * enter it again.
 */
class StoreSupplierPaymentRequest extends FormRequest
{
    public const MAX_ALLOCATIONS = 100;

    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if (is_string($this->input('reference'))) {
            $this->merge(['reference' => trim($this->input('reference')) ?: null]);
        }
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;
        $max = StoreSupplierInvoiceRequest::MAX_TOTAL_MINOR;

        return [
            'branch_id' => ['required', 'integer', Rule::exists('branches', 'id')->where('restaurant_id', $tenant)],
            'supplier_id' => ['required', 'integer', Rule::exists('suppliers', 'id')->where('restaurant_id', $tenant)],
            'method' => ['required', Rule::enum(SupplierPaymentMethod::class)],
            'amount_minor' => ['required', 'integer', 'min:1', 'max:'.$max],
            'reference' => ['nullable', 'string', 'max:120'],
            'paid_at' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.$this->user()->restaurant->today()],
            'note' => ['nullable', 'string', 'max:2000'],
            'pos_cash_movement_id' => ['nullable', 'integer', Rule::exists('pos_cash_movements', 'id')->where('restaurant_id', $tenant)],
            'allocations' => ['sometimes', 'array', 'max:'.self::MAX_ALLOCATIONS],
            'allocations.*' => ['array'],
            'allocations.*.supplier_invoice_id' => ['required', 'integer', 'distinct', Rule::exists('supplier_invoices', 'id')->where('restaurant_id', $tenant)],
            'allocations.*.amount_minor' => ['required', 'integer', 'min:1', 'max:'.$max],
        ];
    }

    public function messages(): array
    {
        return [
            'branch_id.exists' => __('xorder.validation.po_branch'),
            'supplier_id.exists' => __('xorder.validation.po_supplier'),
            'paid_at.before_or_equal' => __('xorder.validation.payment_paid_future'),
            'pos_cash_movement_id.exists' => __('xorder.purchasing.drawer_unknown'),
            'allocations.*.supplier_invoice_id.exists' => __('xorder.validation.payment_invoice'),
            'allocations.*.supplier_invoice_id.distinct' => __('xorder.validation.payment_invoice_twice'),
        ];
    }
}
