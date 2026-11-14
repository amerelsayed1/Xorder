<?php

namespace App\Http\Requests\Dashboard;

use App\Services\UnitCatalog;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice b: a purchase-order draft, header and lines, written whole (the
 * till's editor replaces the lines wholesale, and so does PUT).
 *
 * Shape only. Everything that depends on other rows (a retired supplier,
 * item or unit; a fraction on a whole unit; editing anything but a draft) is
 * decided by PurchaseOrderService inside its transaction, under the lock.
 *
 * Every id in the body must be this business's: a foreign branch, supplier,
 * stock item or unit is a 422 here, never a silent cross-tenant write.
 *
 * Money is integer minor units and a quantity integer thousandths, as on the
 * till. The caps keep every product in StockCosting inside a 64-bit int:
 * a line is at most 10^12 minor units and an order at most 100 lines, so the
 * per-rate tax (base × 10^4) stays below 10^18.
 */
class StorePurchaseOrderRequest extends FormRequest
{
    public const MAX_LINES = 100;

    public const MAX_QUANTITY_MILLI = 1_000_000_000;

    public const MAX_UNIT_COST_MINOR = 10_000_000_000;

    /** milli × unit cost, i.e. a line's value × 1000. */
    public const MAX_LINE_PRODUCT = 1_000_000_000_000_000;

    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        // A business may raise its first order before it ever opened the
        // Units page; the seven defaults must exist for `kg` to validate.
        app(UnitCatalog::class)->ensureDefaults($this->user()->restaurant_id);

        $lines = $this->input('lines');
        if (is_array($lines)) {
            foreach ($lines as $i => $line) {
                if (! is_array($line)) {
                    continue;
                }
                if (isset($line['unit_code']) && is_string($line['unit_code'])) {
                    $lines[$i]['unit_code'] = strtolower(trim($line['unit_code']));
                }
                if (isset($line['description']) && is_string($line['description'])) {
                    $lines[$i]['description'] = trim($line['description']);
                }
            }
            $this->merge(['lines' => $lines]);
        }
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;

        return [
            'branch_id' => ['required', 'integer', Rule::exists('branches', 'id')->where('restaurant_id', $tenant)],
            'supplier_id' => ['required', 'integer', Rule::exists('suppliers', 'id')->where('restaurant_id', $tenant)],
            'expected_at' => ['nullable', 'date_format:Y-m-d'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'lines' => ['present', 'array', 'max:'.self::MAX_LINES],
            'lines.*' => ['array'],
            'lines.*.stock_item_id' => ['nullable', 'integer', Rule::exists('stock_items', 'id')->where('restaurant_id', $tenant)],
            'lines.*.description' => ['nullable', 'string', 'max:200', 'required_without:lines.*.stock_item_id'],
            'lines.*.sku' => ['nullable', 'string', 'max:64'],
            'lines.*.unit_code' => [
                'nullable', 'string', 'max:16', 'required_without:lines.*.stock_item_id',
                Rule::exists('units', 'code')->where('restaurant_id', $tenant),
            ],
            'lines.*.quantity_milli' => ['required', 'integer', 'min:1', 'max:'.self::MAX_QUANTITY_MILLI],
            'lines.*.unit_cost_minor' => ['required', 'integer', 'min:0', 'max:'.self::MAX_UNIT_COST_MINOR],
            'lines.*.tax_rate_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            foreach ((array) $this->input('lines', []) as $i => $line) {
                $milli = $line['quantity_milli'] ?? null;
                $cost = $line['unit_cost_minor'] ?? null;
                if (is_int($milli) && is_int($cost) && $cost > 0 && $milli > intdiv(self::MAX_LINE_PRODUCT, $cost)) {
                    $validator->errors()->add("lines.$i.quantity_milli", __('xorder.validation.po_line_too_large'));
                }
            }
        });
    }

    public function messages(): array
    {
        return [
            'branch_id.exists' => __('xorder.validation.po_branch'),
            'supplier_id.exists' => __('xorder.validation.po_supplier'),
            'lines.*.stock_item_id.exists' => __('xorder.validation.po_stock_item'),
            'lines.*.unit_code.exists' => __('xorder.validation.po_unit'),
            'lines.*.description.required_without' => __('xorder.validation.po_line_description'),
            'lines.*.unit_code.required_without' => __('xorder.validation.po_unit'),
        ];
    }
}
