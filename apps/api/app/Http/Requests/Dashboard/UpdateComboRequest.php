<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateComboRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'base_price' => ['sometimes', 'required', 'numeric', 'min:0', 'max:9999999.99'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],

            'groups' => ['sometimes', 'array', 'max:20'],
            'groups.*.name_en' => ['nullable', 'string', 'max:150'],
            'groups.*.name_ar' => ['nullable', 'string', 'max:150'],
            'groups.*.max_select' => ['sometimes', 'integer', 'min:1', 'max:50'],
            'groups.*.items' => ['sometimes', 'array', 'max:50'],
            'groups.*.items.*.menu_item_id' => [
                'required',
                Rule::exists('menu_items', 'id')->where('restaurant_id', $restaurantId),
            ],
            'groups.*.items.*.extra_price' => ['sometimes', 'numeric', 'min:0', 'max:9999999.99'],
        ];
    }
}
