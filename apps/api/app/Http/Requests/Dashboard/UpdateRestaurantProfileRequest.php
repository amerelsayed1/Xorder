<?php

namespace App\Http\Requests\Dashboard;

use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Restaurant Admin profile edit. Deliberately excludes slug, status and
 * subscription fields — those are Super-Admin-only and never accepted here.
 */
class UpdateRestaurantProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('settings.update') ?? false;
    }

    public function rules(): array
    {
        return [
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
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
            // The owner's "are we taking orders right now" switch. The plan
            // still decides whether ordering exists at all (ordering_mode,
            // below) — this only turns an entitled channel on and off.
            'accepts_orders' => ['sometimes', 'boolean'],
            'social_links' => ['nullable', 'array'],
            'social_links.instagram' => ['nullable', 'string', 'url', 'max:2048'],
            'social_links.facebook' => ['nullable', 'string', 'url', 'max:2048'],
            'social_links.tiktok' => ['nullable', 'string', 'url', 'max:2048'],
            // Branding (brand_color, secondary_color), default_language and the
            // ordering channel (ordering_mode) are NOT editable here — they are
            // set by the Super Admin per the restaurant's plan. Any such keys in
            // the payload are ignored (never reach ->update(validated())).
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($this->has('name_ar') || $this->has('name_en')) {
                if (blank($this->input('name_ar')) && blank($this->input('name_en'))) {
                    // Report on the default-language name field — the one the
                    // profile form always renders — so single-language
                    // restaurants see the error instead of a silent failure.
                    $lang = $this->user()->restaurant->default_language?->value ?? 'ar';
                    $validator->errors()->add("name_{$lang}", __('xorder.validation.restaurant_name_still_required'));
                }
            }
        });
    }
}
