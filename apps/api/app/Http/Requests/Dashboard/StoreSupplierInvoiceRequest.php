<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice c: a supplier invoice, written whole.
 *
 * Two shapes, as a bookkeeper actually works:
 *   - header only (the till's shape): `total_minor`, plus the tax as
 *     `tax_minor` or as `tax_rate_bp` (the rate INSIDE the total);
 *   - with `lines`: the total and tax are computed from them by the server
 *     with the till's rounding points, and any typed total is ignored.
 *
 * Shape only. What depends on other rows (a duplicate live number, the linked
 * order's supplier, branch and status, editing a paid or voided invoice) is
 * decided by SupplierLedgerService inside its transaction.
 *
 * Every id must be this business's: a foreign branch, supplier or order is a
 * 422 here. Money is integer minor units and a quantity integer thousandths.
 * The caps keep every product inside a 64-bit int (the same as a purchase
 * order's).
 */
class StoreSupplierInvoiceRequest extends FormRequest
{
    public const MAX_LINES = 100;

    /** 10^13 minor units: a hundred billion at two decimals. */
    public const MAX_TOTAL_MINOR = 10_000_000_000_000;

    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if (is_string($this->input('number'))) {
            $this->merge(['number' => trim($this->input('number'))]);
        }
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;
        $today = $this->user()->restaurant->today();
        $noLines = empty($this->input('lines'));

        return [
            'branch_id' => ['required', 'integer', Rule::exists('branches', 'id')->where('restaurant_id', $tenant)],
            'supplier_id' => ['required', 'integer', Rule::exists('suppliers', 'id')->where('restaurant_id', $tenant)],
            'purchase_order_id' => ['nullable', 'integer', Rule::exists('purchase_orders', 'id')->where('restaurant_id', $tenant)],
            'number' => ['required', 'string', 'max:64'],
            // Off the paper, not today: an invoice dated the 3rd and typed on
            // the 20th is due on the supplier's terms from the 3rd.
            'issued_at' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.$today],
            'due_at' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:issued_at'],
            'note' => ['nullable', 'string', 'max:2000'],
            'lines' => ['sometimes', 'array', 'max:'.self::MAX_LINES],
            'lines.*' => ['array'],
            'lines.*.description' => ['required', 'string', 'max:200'],
            'lines.*.quantity_milli' => ['required', 'integer', 'min:1', 'max:'.StorePurchaseOrderRequest::MAX_QUANTITY_MILLI],
            'lines.*.unit_cost_minor' => ['required', 'integer', 'min:0', 'max:'.StorePurchaseOrderRequest::MAX_UNIT_COST_MINOR],
            'lines.*.tax_rate_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
            'total_minor' => [Rule::requiredIf($noLines), 'nullable', 'integer', 'min:1', 'max:'.self::MAX_TOTAL_MINOR],
            'tax_minor' => ['nullable', 'integer', 'min:0', 'max:'.self::MAX_TOTAL_MINOR],
            'tax_rate_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            foreach ((array) $this->input('lines', []) as $i => $line) {
                $milli = $line['quantity_milli'] ?? null;
                $cost = $line['unit_cost_minor'] ?? null;
                if (is_int($milli) && is_int($cost) && $cost > 0 && $milli > intdiv(StorePurchaseOrderRequest::MAX_LINE_PRODUCT, $cost)) {
                    $validator->errors()->add("lines.$i.quantity_milli", __('xorder.validation.po_line_too_large'));
                }
            }

            $total = $this->input('total_minor');
            $tax = $this->input('tax_minor');
            if (empty($this->input('lines')) && is_int($total) && is_int($tax) && $tax > $total) {
                $validator->errors()->add('tax_minor', __('xorder.purchasing.invoice_tax_exceeds_total'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'branch_id.exists' => __('xorder.validation.po_branch'),
            'supplier_id.exists' => __('xorder.validation.po_supplier'),
            'purchase_order_id.exists' => __('xorder.validation.invoice_po'),
            'number.required' => __('xorder.validation.invoice_number_required'),
            'issued_at.before_or_equal' => __('xorder.validation.invoice_issued_future'),
            'due_at.after_or_equal' => __('xorder.validation.invoice_due_before_issue'),
            'total_minor.required' => __('xorder.validation.invoice_total_or_lines'),
            'total_minor.min' => __('xorder.purchasing.invoice_total_not_positive'),
            'lines.*.description.required' => __('xorder.validation.invoice_line_description'),
        ];
    }
}
