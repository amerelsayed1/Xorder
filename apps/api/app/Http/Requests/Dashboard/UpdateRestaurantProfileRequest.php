<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use App\Rules\MobileNumber;
use App\Http\Requests\Concerns\NormalizesNumericInput;
use App\Http\Requests\Concerns\PreservesDisabledLanguages;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Restaurant Admin profile edit. Deliberately excludes slug, status and
 * subscription fields — those are Super-Admin-only and never accepted here.
 */
class UpdateRestaurantProfileRequest extends FormRequest
{
    use NormalizesNumericInput;
    use PreservesDisabledLanguages;

    public function authorize(): bool
    {
        return $this->user()?->can('settings.update') ?? false;
    }

    /**
     * @return list<string>
     */
    protected function numericInputKeys(): array
    {
        return [
            'minimum_order',
        ];
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
            // Content languages (XORD-005): which languages the restaurant writes
            // its menu in. Editable here since 2026-10-25; before that only the
            // Super Admin could change them. The three choices the form offers
            // are bilingual+primary, Arabic only and English only; a request
            // that sends neither key leaves them alone.
            'bilingual' => ['sometimes', 'boolean'],
            'default_language' => ['sometimes', 'in:ar,en'],
            // Branding (brand_color, secondary_color) and the ordering channel
            // (ordering_mode) are NOT editable here — they are set by the Super
            // Admin per the restaurant's plan. Any such keys in the payload are
            // ignored (never reach ->update(validated())).
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            // On the field the profile form renders for the restaurant's content
            // languages — read BEFORE any language change in this same request
            // takes effect, which is what the form on screen was showing.
            ContentLanguages::checkName($this, $validator, 'xorder.validation.restaurant_name_still_required', partial: true, primaryWhenBilingual: true);
        });
    }
}
