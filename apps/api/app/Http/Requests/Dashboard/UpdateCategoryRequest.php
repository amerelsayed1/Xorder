<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateCategoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;
        $categoryId = $this->route('category')->id;

        return [
            'name_ar' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_ar')->where('restaurant_id', $restaurantId)->ignore($categoryId),
            ],
            'name_en' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_en')->where('restaurant_id', $restaurantId)->ignore($categoryId),
            ],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'display_order' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (($this->has('name_ar') || $this->has('name_en'))
                && blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                $validator->errors()->add('name_en', __('xorder.validation.category_name_still_required'));
            }
        });
    }
}
