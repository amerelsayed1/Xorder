<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use App\Enums\LanguageEnum;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateRestaurantRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->route('restaurant')->id;

        return [
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            // Slug is editable (with a loud client-side warning) but must stay unique & valid.
            'slug' => [
                'sometimes', 'required', 'string', 'max:80',
                'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/',
                Rule::notIn(config('platform.reserved_slugs')),
                Rule::unique('restaurants', 'slug')->ignore($restaurantId),
            ],
            'description_ar' => ['nullable', 'string', 'max:2000'],
            'description_en' => ['nullable', 'string', 'max:2000'],
            'logo_url' => ['nullable', 'string', 'max:2048'],
            'cover_image_url' => ['nullable', 'string', 'max:2048'],
            'phone' => ['nullable', 'string', 'max:32'],
            'whatsapp_number' => ['nullable', 'string', 'max:32'],
            'address' => ['nullable', 'string', 'max:1000'],
            'opening_hours' => ['nullable', 'string', 'max:2000'],
            'brand_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'secondary_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'default_language' => ['sometimes', 'required', Rule::enum(LanguageEnum::class)],
            'bilingual' => ['sometimes', 'boolean'],
            'currency' => ['sometimes', 'required', Rule::enum(CurrencyEnum::class)],
            'ordering_enabled' => ['sometimes', 'boolean'],
            'features' => ['sometimes', 'array'],
            'features.*' => ['boolean'],
        ];
    }

    public function messages(): array
    {
        return [
            'slug.regex' => __('xorder.validation.slug_regex'),
        ];
    }
}
