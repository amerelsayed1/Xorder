<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
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
            'features' => ['nullable', 'array'],
            'features.*' => ['string', 'max:255'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
