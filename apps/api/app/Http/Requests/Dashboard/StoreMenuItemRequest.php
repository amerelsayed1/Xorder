<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreMenuItemRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            // category must belong to THIS restaurant (never trust the id blindly).
            'category_id' => [
                'required',
                Rule::exists('categories', 'id')->where('restaurant_id', $restaurantId),
            ],
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'price' => ['required', 'numeric', 'min:0', 'max:9999999.99'],
            'discounted_price' => ['nullable', 'numeric', 'min:0', 'lt:price'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'is_available' => ['nullable', 'boolean'],
            'is_featured' => ['nullable', 'boolean'],
            'display_order' => ['nullable', 'integer', 'min:0'],

            // Option groups (sizes, add-ons, "without …") with nested options.
            'option_groups' => ['sometimes', 'array', 'max:20'],
            'option_groups.*.name_en' => ['nullable', 'string', 'max:150'],
            'option_groups.*.name_ar' => ['nullable', 'string', 'max:150'],
            'option_groups.*.is_required' => ['sometimes', 'boolean'],
            'option_groups.*.max_select' => ['sometimes', 'integer', 'min:1', 'max:50'],
            'option_groups.*.options' => ['sometimes', 'array', 'max:50'],
            'option_groups.*.options.*.name_en' => ['nullable', 'string', 'max:150'],
            'option_groups.*.options.*.name_ar' => ['nullable', 'string', 'max:150'],
            'option_groups.*.options.*.price' => ['sometimes', 'numeric', 'min:0', 'max:9999999.99'],
            'option_groups.*.options.*.is_available' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                // Attach to the restaurant's default-language name field — that's
                // the one the form always renders (a single-language menu only
                // shows its default), so the error is actually visible.
                $lang = $this->user()->restaurant->default_language?->value ?? 'ar';
                $validator->errors()->add("name_{$lang}", __('xorder.validation.item_name_required'));
            }
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
