<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use App\Http\Requests\Concerns\PreservesDisabledLanguages;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateCategoryRequest extends FormRequest
{
    use PreservesDisabledLanguages;

    public function authorize(): bool
    {
        return $this->user()?->can('menu.update') ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;
        $categoryId = $this->route('category')->id;

        return [
            'name_ar' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_ar')->where('restaurant_id', $restaurantId)->whereNull('deleted_at')->ignore($categoryId),
            ],
            'name_en' => [
                'nullable', 'string', 'max:150',
                Rule::unique('categories', 'name_en')->where('restaurant_id', $restaurantId)->whereNull('deleted_at')->ignore($categoryId),
            ],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'image_url' => ['nullable', 'string', 'max:2048'],
            'display_order' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            // Per-weekday serving times; null/absent = served whenever the menu is.
            'availability_hours' => ['nullable', 'array'],
            'availability_hours.*.closed' => ['sometimes', 'boolean'],
            'availability_hours.*.always' => ['sometimes', 'boolean'],
            'availability_hours.*.open' => ['nullable', 'date_format:H:i'],
            'availability_hours.*.close' => ['nullable', 'date_format:H:i'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.category_name_still_required', partial: true);
        });
    }
}
