<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

class StoreOptionGroupRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        return [
            'name_en' => ['nullable', 'string', 'max:150'],
            'name_ar' => ['nullable', 'string', 'max:150'],
            'is_required' => ['sometimes', 'boolean'],
            'is_variant' => ['sometimes', 'boolean'],
            'max_select' => ['sometimes', 'integer', 'min:1', 'max:50'],
            'options' => ['sometimes', 'array', 'max:50'],
            'options.*.name_en' => ['nullable', 'string', 'max:150'],
            'options.*.name_ar' => ['nullable', 'string', 'max:150'],
            'options.*.price' => ['sometimes', 'numeric', 'min:0', 'max:9999999.99'],
            'options.*.is_available' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                $lang = $this->user()->restaurant->default_language?->value ?? 'ar';
                $validator->errors()->add("name_{$lang}", __('xorder.validation.option_group_name_required'));
            }
        });
    }
}
