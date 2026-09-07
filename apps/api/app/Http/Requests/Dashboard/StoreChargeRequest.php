<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-013: exactly one of rate_bp (percent) / amount_minor (fixed) per the
 * declared kind — the other must be absent or null.
 */
class StoreChargeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'kind' => ['required', 'in:percent,fixed'],
            'rate_bp' => ['required_if:kind,percent', 'prohibited_if:kind,fixed', 'nullable', 'integer', 'min:0', 'max:10000'],
            'amount_minor' => ['required_if:kind,fixed', 'prohibited_if:kind,percent', 'nullable', 'integer', 'min:0'],
            'taxable' => ['nullable', 'boolean'],
            'applies_to' => ['nullable', 'array'],
            'applies_to.order_types' => ['nullable', 'array'],
            'applies_to.order_types.*' => ['string', 'max:20'],
            'applies_to.branch_ids' => ['nullable', 'array'],
            'applies_to.branch_ids.*' => ['integer'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
