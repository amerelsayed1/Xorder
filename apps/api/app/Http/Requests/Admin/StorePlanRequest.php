<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StorePlanRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:100', Rule::unique('plans', 'name')],
            'price' => ['nullable', 'numeric', 'min:0', 'max:99999999'],
            'currency' => ['required', Rule::enum(CurrencyEnum::class)],
            'features' => ['nullable', 'array'],
            'features.*' => ['string', 'max:255'],
            'max_items' => ['nullable', 'integer', 'min:1', 'max:100000'],
            'max_branches' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'is_active' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
