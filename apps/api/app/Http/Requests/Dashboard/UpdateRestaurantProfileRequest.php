<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\MenuLayout;
use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Restaurant Admin profile edit. Deliberately excludes slug, status and
 * subscription fields — those are Super-Admin-only and never accepted here.
 * Since 2026-11-03 it includes the brand colour and the menu layout.
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
            // The taxpayer's registration number — ETA's `rin`, nine digits in
            // Egypt. Accepted here since 2026-09-22 (A3): the column shipped
            // with Cloud Wave 1 and travelled in the POS bundle, but nothing
            // could set it except tinker, which is CLOUD_WAVE1 deviation 6.
            // Shape is not enforced: a half-typed number must be savable, and
            // the till already decides per field what is enough to print
            // versus enough to FILE (ReceiptProfile.filingProblems).
            'tax_registration_number' => ['nullable', 'string', 'max:32'],
            // Decides when the restaurant's day turns over: every "today" on the
            // dashboard (menu views, order counts, reports) is measured in this
            // zone. `timezone:all` accepts any IANA identifier PHP knows.
            'timezone' => ['nullable', 'string', 'max:64', 'timezone:all'],
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
            // The menu's look is the owner's call (owner decision 2026-11-03):
            // the brand colour tints the public menu and the till's accent,
            // the layout picks photos or a text-only menu. The colour column is
            // NOT NULL, so it can be changed but never cleared.
            'brand_color' => ['sometimes', 'required', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'menu_layout' => ['sometimes', 'required', Rule::enum(MenuLayout::class)],
            // secondary_color, default_language and the ordering channel
            // (ordering_mode) stay Super-Admin-only: the public menu does not
            // use a second colour yet, and the other two follow the plan. Any
            // such keys in the payload are ignored (never reach
            // ->update(validated())).
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
