<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use App\Enums\LanguageEnum;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class StoreRestaurantRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        return [
            // Restaurant — at least one name required (enforced in withValidator).
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'slug' => [
                'required', 'string', 'max:80',
                'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/',
                Rule::notIn(config('platform.reserved_slugs')),
                Rule::unique('restaurants', 'slug'),
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
            'default_language' => ['required', Rule::enum(LanguageEnum::class)],
            'bilingual' => ['nullable', 'boolean'],
            'currency' => ['required', Rule::enum(CurrencyEnum::class)],
            'ordering_enabled' => ['nullable', 'boolean'],
            'status' => ['nullable', Rule::enum(RestaurantStatus::class)],
            'subscription_status' => ['nullable', Rule::enum(SubscriptionStatus::class)],
            'subscription_plan' => ['nullable', 'string', 'max:100'],
            'subscription_start_date' => ['nullable', 'date'],
            'subscription_end_date' => ['nullable', 'date', 'after_or_equal:subscription_start_date'],

            // First Restaurant Admin.
            'admin.name' => ['required', 'string', 'max:150'],
            'admin.email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'admin.password' => ['nullable', 'string', Password::min(8)],

            // Feature flags (Step 5). Unknown keys are ignored by Feature::resolve.
            'features' => ['nullable', 'array'],
            'features.*' => ['boolean'],

            // Optional first branch (Step 4). Omit the object entirely to skip.
            'branch' => ['nullable', 'array'],
            'branch.name_ar' => ['nullable', 'string', 'max:150'],
            'branch.name_en' => ['nullable', 'string', 'max:150'],
            'branch.code' => ['nullable', 'string', 'max:40'],
            'branch.city' => ['nullable', 'string', 'max:120'],
            'branch.country' => ['nullable', 'string', 'size:2'],
            'branch.address' => ['nullable', 'string', 'max:1000'],
            'branch.phone' => ['nullable', 'string', 'max:32'],
            'branch.whatsapp_number' => ['nullable', 'string', 'max:32'],
            'branch.supported_order_types' => ['nullable', 'array'],
            'branch.supported_order_types.*' => ['string', Rule::in(['dine_in', 'pickup', 'delivery'])],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                $validator->errors()->add('name_en', __('xorder.validation.restaurant_name_required'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'slug.regex' => __('xorder.validation.slug_regex'),
        ];
    }
}
