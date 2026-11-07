<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use App\Http\Requests\Concerns\OptionDiscountValidation;
use App\Http\Requests\Concerns\NormalizesNumericInput;
use App\Http\Requests\Concerns\PreservesDisabledLanguages;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateMenuItemRequest extends FormRequest
{
    use NormalizesNumericInput;
    use PreservesDisabledLanguages;

    public function authorize(): bool
    {
        return $this->user()?->can('menu.update') ?? false;
    }

    /**
     * @return list<string>
     */
    protected function numericInputKeys(): array
    {
        return [
            'price',
            'discounted_price',
            'option_groups.*.options.*.price',
            'option_groups.*.options.*.discounted_price',
        ];
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            'category_id' => [
                'sometimes', 'required',
                // whereNull: Rule::exists() does not skip soft-deleted rows (XORD-014).
                Rule::exists('categories', 'id')->where('restaurant_id', $restaurantId)->whereNull('deleted_at'),
            ],
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'price' => ['sometimes', 'required', 'numeric', 'min:0', 'max:9999999.99'],
            'discounted_price' => ['nullable', 'numeric', 'min:0', 'lt:price'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'is_available' => ['nullable', 'boolean'],
            'is_featured' => ['nullable', 'boolean'],
            'display_order' => ['nullable', 'integer', 'min:0'],

            'option_groups' => ['sometimes', 'array', 'max:20'],
            'option_groups.*.ref' => ['sometimes', 'in:inline,shared'],
            'option_groups.*.option_group_id' => ['required_if:option_groups.*.ref,shared', 'integer'],
            'option_groups.*.name_en' => ['nullable', 'string', 'max:150'],
            'option_groups.*.name_ar' => ['nullable', 'string', 'max:150'],
            'option_groups.*.is_required' => ['sometimes', 'boolean'],
            'option_groups.*.is_variant' => ['sometimes', 'boolean'],
            'option_groups.*.max_select' => ['sometimes', 'integer', 'min:1', 'max:50'],
            'option_groups.*.options' => ['sometimes', 'array', 'max:50'],
            'option_groups.*.options.*.name_en' => ['nullable', 'string', 'max:150'],
            'option_groups.*.options.*.name_ar' => ['nullable', 'string', 'max:150'],
            'option_groups.*.options.*.price' => ['sometimes', 'numeric', 'min:0', 'max:9999999.99'],
            // Sale price for a size option; must undercut its own price (checked
            // in withValidator, see OptionDiscountValidation).
            'option_groups.*.options.*.discounted_price' => ['nullable', 'numeric', 'min:0', 'max:9999999.99'],
            'option_groups.*.options.*.is_available' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.item_name_still_required', partial: true, primaryWhenBilingual: true);

            OptionDiscountValidation::checkItemGroups($this, $validator);
        });
    }

    public function messages(): array
    {
        return [
            'discounted_price.lt' => __('xorder.validation.discounted_price_lt'),
            'category_id.exists' => __('xorder.validation.category_wrong_restaurant'),
        ];
    }
}
