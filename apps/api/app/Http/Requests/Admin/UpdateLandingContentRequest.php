<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

class UpdateLandingContentRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Route is already gated by auth:sanctum + role:SUPER_ADMIN.
        return true;
    }

    /**
     * Validate the landing content document. Bilingual leaves are { en, ar }
     * string pairs; repeaters (proof, features.items, steps.items,
     * pricing.plans) are arrays the admin can add to, remove from, and reorder.
     */
    public function rules(): array
    {
        $bi = fn (string $path) => [
            "$path" => ['required', 'array'],
            "$path.en" => ['nullable', 'string', 'max:2000'],
            "$path.ar" => ['nullable', 'string', 'max:2000'],
        ];

        return array_merge(
            ['content' => ['required', 'array']],

            // Hero
            $bi('content.hero.badge'),
            $bi('content.hero.title'),
            $bi('content.hero.sub'),
            $bi('content.hero.cta'),
            $bi('content.hero.secondary'),

            // Proof points (repeater)
            ['content.proof' => ['present', 'array', 'max:12']],
            $bi('content.proof.*.title'),
            $bi('content.proof.*.text'),

            // Features
            $bi('content.features.title'),
            $bi('content.features.sub'),
            ['content.features.items' => ['present', 'array', 'max:24']],
            ['content.features.items.*.icon' => ['nullable', 'string', 'max:8']],
            $bi('content.features.items.*.title'),
            $bi('content.features.items.*.text'),

            // Steps
            $bi('content.steps.title'),
            ['content.steps.items' => ['present', 'array', 'max:12']],
            $bi('content.steps.items.*.title'),
            $bi('content.steps.items.*.text'),

            // Pricing
            $bi('content.pricing.title'),
            $bi('content.pricing.sub'),
            $bi('content.pricing.popular_label'),
            $bi('content.pricing.choose_label'),
            ['content.pricing.plans' => ['present', 'array', 'max:8']],
            $bi('content.pricing.plans.*.name'),
            $bi('content.pricing.plans.*.price'),
            $bi('content.pricing.plans.*.per'),
            $bi('content.pricing.plans.*.note'),
            ['content.pricing.plans.*.popular' => ['required', 'boolean']],
            ['content.pricing.plans.*.features' => ['present', 'array', 'max:24']],
            $bi('content.pricing.plans.*.features.*'),

            // CTA
            $bi('content.cta.title'),
            $bi('content.cta.sub'),
            $bi('content.cta.button'),
            $bi('content.cta.whatsapp_label'),

            // Contact
            ['content.contact' => ['required', 'array']],
            ['content.contact.email' => ['nullable', 'string', 'email', 'max:255']],
            ['content.contact.whatsapp' => ['nullable', 'string', 'max:32']],

            // Footer
            $bi('content.footer.tagline'),
            $bi('content.footer.rights'),
        );
    }
}
