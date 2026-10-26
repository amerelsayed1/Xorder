<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use App\Http\Requests\Concerns\OptionDiscountValidation;
use App\Models\OptionGroup;
use App\Http\Requests\Concerns\NormalizesNumericInput;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreOptionGroupRequest extends FormRequest
{
    use NormalizesNumericInput;

    public function authorize(): bool
    {
        return $this->user()?->can('menu.create') ?? false;
    }

    /**
     * @return list<string>
     */
    protected function numericInputKeys(): array
    {
        return [
            'options.*.price',
            'options.*.discounted_price',
        ];
    }

    public function rules(): array
    {
        return [
            'name_en' => ['nullable', 'string', 'max:150'],
            'name_ar' => ['nullable', 'string', 'max:150'],
            // Diner-facing heading; optional, falls back to the library name.
            'display_name_en' => ['nullable', 'string', 'max:150'],
            'display_name_ar' => ['nullable', 'string', 'max:150'],
            'is_required' => ['sometimes', 'boolean'],
            'is_variant' => ['sometimes', 'boolean'],
            'max_select' => ['sometimes', 'integer', 'min:1', 'max:50'],
            'apply_scope' => ['sometimes', Rule::in([OptionGroup::SCOPE_ITEMS, OptionGroup::SCOPE_CATEGORIES, OptionGroup::SCOPE_ALL])],
            'category_ids' => ['sometimes', 'array', 'max:100'],
            'category_ids.*' => ['integer', Rule::exists('categories', 'id')->where('restaurant_id', $this->user()->restaurant_id)],
            'options' => ['sometimes', 'array', 'max:50'],
            'options.*.name_en' => ['nullable', 'string', 'max:150'],
            'options.*.name_ar' => ['nullable', 'string', 'max:150'],
            'options.*.price' => ['sometimes', 'numeric', 'min:0', 'max:9999999.99'],
            'options.*.discounted_price' => ['nullable', 'numeric', 'min:0', 'max:9999999.99'],
            'options.*.is_available' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.option_group_name_required', primaryWhenBilingual: true);

            if ($this->input('apply_scope') === OptionGroup::SCOPE_CATEGORIES
                && count($this->input('category_ids') ?? []) === 0) {
                $validator->errors()->add('category_ids', __('xorder.validation.option_group_categories_required'));
            }

            OptionDiscountValidation::checkGroup($this, $validator);
        });
    }
}
