<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use App\Enums\Feature;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdatePlanRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        $planId = $this->route('plan')->id;

        return [
            'name' => ['sometimes', 'required', 'string', 'max:100', Rule::unique('plans', 'name')->ignore($planId)],
            'price' => ['nullable', 'numeric', 'min:0', 'max:99999999'],
            'currency' => ['sometimes', 'required', Rule::enum(CurrencyEnum::class)],
            // Machine-readable capability entitlements (Feature enum values).
            'feature_keys' => ['nullable', 'array'],
            'feature_keys.*' => ['string', Rule::in(Feature::values())],
            'max_items' => ['nullable', 'integer', 'min:1', 'max:100000'],
            'max_branches' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
