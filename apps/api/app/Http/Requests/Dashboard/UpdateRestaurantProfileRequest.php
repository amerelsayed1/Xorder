<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\OrderingMode;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Restaurant Admin profile edit. Deliberately excludes slug, status and
 * subscription fields — those are Super-Admin-only and never accepted here.
 */
class UpdateRestaurantProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
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
            'phone' => ['nullable', 'string', 'max:32'],
            'whatsapp_number' => ['nullable', 'string', 'max:32'],
            'address' => ['nullable', 'string', 'max:1000'],
            'opening_hours' => ['nullable', 'string', 'max:2000'],
            'social_links' => ['nullable', 'array'],
            'social_links.instagram' => ['nullable', 'string', 'url', 'max:2048'],
            'social_links.facebook' => ['nullable', 'string', 'url', 'max:2048'],
            'social_links.tiktok' => ['nullable', 'string', 'url', 'max:2048'],
            // Branding (brand_color, secondary_color) and default_language are
            // NOT editable here — they are set by the Super Admin. Any such keys
            // in the payload are ignored (never reach ->update(validated())).
            'ordering_mode' => ['sometimes', Rule::enum(OrderingMode::class)],
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
