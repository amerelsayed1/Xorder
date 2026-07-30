<?php

namespace App\Http\Requests\Admin;

use App\Enums\CurrencyEnum;
use App\Enums\LanguageEnum;
use App\Enums\MenuLayout;
use App\Enums\OrderingMode;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class StoreRestaurantRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('restaurants.manage') ?? false;
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
            'phone' => ['nullable', 'string', 'max:32', (new MobileNumber)->allowLandline()],
            'whatsapp_number' => ['nullable', 'string', 'max:32', new MobileNumber],
            'address' => ['nullable', 'string', 'max:1000'],
            'opening_hours' => ['nullable', 'string', 'max:2000'],
            'brand_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'secondary_color' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'menu_layout' => ['nullable', Rule::enum(MenuLayout::class)],
            'default_language' => ['required', Rule::enum(LanguageEnum::class)],
            'bilingual' => ['nullable', 'boolean'],
            'currency' => ['required', Rule::enum(CurrencyEnum::class)],
            'ordering_mode' => ['nullable', Rule::enum(OrderingMode::class)],
            'status' => ['nullable', Rule::enum(RestaurantStatus::class)],
            'subscription_status' => ['nullable', Rule::enum(SubscriptionStatus::class)],
            'subscription_plan' => ['nullable', 'string', 'max:100'],
            'subscription_start_date' => ['nullable', 'date'],
            'subscription_end_date' => ['nullable', 'date', 'after_or_equal:subscription_start_date'],

            // First Restaurant Admin.
            'admin.name' => ['required', 'string', 'max:150'],
            // Unique per tenant, enforced by the DB index; a brand-new
            // restaurant has no users yet, so no cross-tenant check is needed here.
            'admin.username' => ['required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/'],
            'admin.email' => ['nullable', 'email', 'max:255', Rule::unique('users', 'email')],
            'admin.password' => ['nullable', 'string', Password::min(8)],

            // Capabilities are NOT accepted here: a client's features are strictly
            // derived from its subscription_plan (PlanEntitlementService). Any
            // hand-passed feature map would conflict with the plan, so the wizard
            // sends only the plan and the server resolves the rest.

            // Optional first branch (Step 4). Omit the object entirely to skip.
            'branch' => ['nullable', 'array'],
            'branch.name_ar' => ['nullable', 'string', 'max:150'],
            'branch.name_en' => ['nullable', 'string', 'max:150'],
            'branch.code' => ['nullable', 'string', 'max:40'],
            'branch.city' => ['nullable', 'string', 'max:120'],
            'branch.country' => ['nullable', 'string', 'size:2'],
            'branch.address' => ['nullable', 'string', 'max:1000'],
            'branch.phone' => ['nullable', 'string', 'max:32', (new MobileNumber)->allowLandline()],
            'branch.whatsapp_number' => ['nullable', 'string', 'max:32', new MobileNumber],
            'branch.supported_order_types' => ['nullable', 'array'],
            'branch.supported_order_types.*' => ['string', Rule::in(['dine_in', 'pickup', 'delivery'])],
        ];
    }

    /** Usernames are case-insensitive; normalise before unique + storage. */
    protected function prepareForValidation(): void
    {
        $username = $this->input('admin.username');
        if ($username !== null) {
            $this->merge(['admin' => [...$this->input('admin', []), 'username' => mb_strtolower(trim((string) $username))]]);
        }
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
