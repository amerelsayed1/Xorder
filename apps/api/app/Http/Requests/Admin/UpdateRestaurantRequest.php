<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use App\Enums\LanguageEnum;
use App\Enums\OrderingMode;
use App\Rules\MobileNumber;
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
            'phone' => ['nullable', 'string', 'max:32', (new MobileNumber)->allowLandline()],
            'whatsapp_number' => ['nullable', 'string', 'max:32', new MobileNumber],
            'address' => ['nullable', 'string', 'max:1000'],
            'opening_hours' => ['nullable', 'string', 'max:2000'],
            'business_hours' => ['nullable', 'array'],
            'business_hours.*.closed' => ['sometimes', 'boolean'],
            'business_hours.*.always' => ['sometimes', 'boolean'],
            'business_hours.*.open' => ['nullable', 'date_format:H:i'],
            'business_hours.*.close' => ['nullable', 'date_format:H:i'],
            'delivery_time_min' => ['nullable', 'integer', 'min:0', 'max:1440'],
            'delivery_time_max' => ['nullable', 'integer', 'min:0', 'max:1440', 'gte:delivery_time_min'],
            'minimum_order' => ['nullable', 'numeric', 'min:0', 'max:1000000'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90', 'required_with:longitude'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180', 'required_with:latitude'],
            'brand_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'secondary_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'default_language' => ['sometimes', 'required', Rule::enum(LanguageEnum::class)],
            'bilingual' => ['sometimes', 'boolean'],
            'currency' => ['sometimes', 'required', Rule::enum(CurrencyEnum::class)],
            'ordering_mode' => ['sometimes', Rule::enum(OrderingMode::class)],
            // The plan strictly decides features; changing it here re-derives them.
            'subscription_plan' => ['sometimes', 'nullable', 'string', 'max:100'],
            // Accepted for backward-compat but ignored — features come from the plan.
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
