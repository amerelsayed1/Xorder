<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateMenuItemRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            'category_id' => [
                'sometimes', 'required',
                Rule::exists('categories', 'id')->where('restaurant_id', $restaurantId),
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
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (($this->has('name_ar') || $this->has('name_en'))
                && blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                $validator->errors()->add('name_en', 'The item must have a name in at least one language.');
            }
        });
    }

    public function messages(): array
    {
        return [
            'discounted_price.lt' => 'The discounted price must be lower than the original price.',
            'category_id.exists' => 'The selected category does not belong to your restaurant.',
        ];
    }
}
