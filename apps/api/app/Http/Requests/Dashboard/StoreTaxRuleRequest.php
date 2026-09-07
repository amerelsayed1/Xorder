<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-013: rate is integer BASIS POINTS (1400 = 14%), never a float. */
class StoreTaxRuleRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'rate_bp' => ['required', 'integer', 'min:0', 'max:10000'],
            'mode' => ['required', 'in:inclusive,exclusive'],
            'applies_to' => ['nullable', 'array'],
            'applies_to.order_types' => ['nullable', 'array'],
            'applies_to.order_types.*' => ['string', 'max:20'],
            'applies_to.branch_ids' => ['nullable', 'array'],
            'applies_to.branch_ids.*' => ['integer'],
            'applies_to.category_ids' => ['nullable', 'array'],
            'applies_to.category_ids.*' => ['integer'],
            'applies_to.item_ids' => ['nullable', 'array'],
            'applies_to.item_ids.*' => ['integer'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
