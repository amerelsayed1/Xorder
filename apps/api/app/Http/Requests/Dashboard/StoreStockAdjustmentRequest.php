<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\StockAdjustmentReason;
use App\Services\UnitCatalog;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice d: one stock entry that is not a delivery.
 *
 *   {branch_id, stock_item_id, kind, quantity_milli?, counted_milli?,
 *    unit_cost_minor?, unit_code?, reason?, note?, occurred_at?}
 *
 *   kind = opening     quantity_milli > 0 at unit_cost_minor (required),
 *                      entering at moving-average cost like a receipt
 *   kind = waste       quantity_milli > 0 leaves at the average; no cost
 *   kind = adjustment  quantity_milli signed, never 0. Up: at unit_cost_minor,
 *                      or the current average when omitted. Down: at the
 *                      average; no cost
 *   kind = count       counted_milli >= 0; the server posts counted − recorded,
 *                      read under the level lock, never the page's figure
 *
 * Quantities are integer thousandths, money integer minor units. `unit_code`
 * is the unit the page showed: the service refuses it if the item is now
 * counted in another one, so a stale page never books 2.5 g as 2.5 kg.
 *
 * Branch and stock item must be this business's (a foreign id is a 422, the
 * tender_type_id precedent). Everything that depends on the current position
 * (unit held, cost available, the count's difference, one opening per
 * branch) is StockAdjustmentService's, under its lock.
 */
class StoreStockAdjustmentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        // The whole-unit rule reads the item's unit row; the seven defaults
        // must exist even if the Units page was never opened.
        app(UnitCatalog::class)->ensureDefaults($this->user()->restaurant_id);
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;
        $max = StorePurchaseOrderRequest::MAX_QUANTITY_MILLI;

        return [
            'branch_id' => ['required', 'integer', Rule::exists('branches', 'id')->where('restaurant_id', $tenant)],
            'stock_item_id' => ['required', 'integer', Rule::exists('stock_items', 'id')->where('restaurant_id', $tenant)],
            'kind' => ['required', 'string', Rule::in(StockAdjustmentReason::KINDS)],
            'quantity_milli' => ['required_unless:kind,count', 'prohibited_if:kind,count', 'integer', 'between:-'.$max.','.$max],
            'counted_milli' => ['required_if:kind,count', 'prohibited_unless:kind,count', 'integer', 'min:0', 'max:'.$max],
            'unit_cost_minor' => ['nullable', 'required_if:kind,opening', 'prohibited_if:kind,waste', 'integer', 'min:0', 'max:'.StorePurchaseOrderRequest::MAX_UNIT_COST_MINOR],
            'unit_code' => ['nullable', 'string', 'max:16'],
            'reason' => ['nullable', 'required_if:kind,waste,adjustment', Rule::enum(StockAdjustmentReason::class)],
            'note' => ['nullable', 'string', 'max:1000', 'required_if:reason,'.StockAdjustmentReason::OTHER->value],
            // Backdated is fine; ahead of time is not (clock drift tolerated),
            // as for a receipt. The ledger folds in id order either way.
            'occurred_at' => ['nullable', 'date', 'before_or_equal:'.now()->addMinutes(10)->toIso8601String()],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($v) {
            if ($v->errors()->isNotEmpty()) {
                return;
            }
            $kind = $this->input('kind');
            $quantity = (int) $this->input('quantity_milli');

            if (in_array($kind, ['opening', 'waste'], true) && $quantity <= 0) {
                $v->errors()->add('quantity_milli', __('xorder.validation.adjustment_quantity_positive'));
            }
            if ($kind === 'adjustment' && $quantity === 0) {
                $v->errors()->add('quantity_milli', __('xorder.validation.adjustment_quantity_nonzero'));
            }
            if ($kind === 'adjustment' && $quantity < 0 && $this->filled('unit_cost_minor')) {
                $v->errors()->add('unit_cost_minor', __('xorder.validation.adjustment_cost_not_for_issue'));
            }

            $reason = $this->input('reason');
            if ($reason !== null && ! in_array(StockAdjustmentReason::from($reason), StockAdjustmentReason::forKind($kind), true)) {
                $v->errors()->add('reason', __('xorder.validation.adjustment_reason'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'note.required_if' => __('xorder.validation.void_note_required'),
            'unit_cost_minor.prohibited_if' => __('xorder.validation.adjustment_cost_not_for_issue'),
        ];
    }

    /** @return array<string,mixed> validated, with the implied reason filled in */
    public function entry(): array
    {
        $data = $this->validated();
        $data['reason'] = isset($data['reason'])
            ? StockAdjustmentReason::from($data['reason'])
            : StockAdjustmentReason::defaultFor($data['kind']);

        return $data;
    }
}
