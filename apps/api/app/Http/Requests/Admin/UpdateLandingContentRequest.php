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
     * string pairs; repeaters are arrays the admin can add to, remove from, and
     * reorder. Note: only validated keys survive ($request->validated()), so
     * every persisted field must appear here.
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
            $bi('content.hero.no_commission_label'),
            $bi('content.hero.ready_label'),
            $bi('content.hero.whatsapp_label'),
            ['content.hero.primary_link' => ['nullable', 'string', 'max:255']],
            ['content.hero.secondary_link' => ['nullable', 'string', 'max:255']],

            // Proof points (repeater)
            ['content.proof' => ['present', 'array', 'max:12']],
            $bi('content.proof.*.title'),
            $bi('content.proof.*.text'),

            // Offer
            $bi('content.offer.title'),
            $bi('content.offer.text'),
            ['content.offer.items' => ['present', 'array', 'max:24']],
            ['content.offer.items.*.icon' => ['nullable', 'string', 'max:8']],
            $bi('content.offer.items.*.text'),

            // Problem / solution
            $bi('content.problem.title'),
            $bi('content.problem.sub'),
            ['content.problem.problems' => ['present', 'array', 'max:12']],
            $bi('content.problem.problems.*.text'),
            $bi('content.problem.solution_title'),
            $bi('content.problem.solution_text'),

            // No commission
            $bi('content.no_commission.title'),
            $bi('content.no_commission.text'),
            $bi('content.no_commission.third_party_title'),
            ['content.no_commission.third_party' => ['present', 'array', 'max:12']],
            $bi('content.no_commission.third_party.*.text'),
            $bi('content.no_commission.xorder_title'),
            ['content.no_commission.xorder' => ['present', 'array', 'max:12']],
            $bi('content.no_commission.xorder.*.text'),

            // Features
            $bi('content.features.title'),
            $bi('content.features.sub'),
            ['content.features.items' => ['present', 'array', 'max:24']],
            ['content.features.items.*.icon' => ['nullable', 'string', 'max:8']],
            $bi('content.features.items.*.title'),
            $bi('content.features.items.*.text'),

            // Demo
            ['content.demo.enabled' => ['required', 'boolean']],
            $bi('content.demo.title'),
            $bi('content.demo.text'),
            $bi('content.demo.button'),
            ['content.demo.restaurant_slug' => ['nullable', 'string', 'max:80']],

            // Steps (ordering flow)
            $bi('content.steps.title'),
            ['content.steps.items' => ['present', 'array', 'max:12']],
            $bi('content.steps.items.*.title'),
            $bi('content.steps.items.*.text'),

            // Packages (pricing)
            $bi('content.pricing.title'),
            $bi('content.pricing.sub'),
            $bi('content.pricing.popular_label'),
            $bi('content.pricing.choose_label'),
            ['content.pricing.plans' => ['present', 'array', 'max:8']],
            $bi('content.pricing.plans.*.name'),
            $bi('content.pricing.plans.*.subtitle'),
            $bi('content.pricing.plans.*.price_label'),
            ['content.pricing.plans.*.recommended' => ['required', 'boolean']],
            ['content.pricing.plans.*.enabled' => ['required', 'boolean']],
            ['content.pricing.plans.*.features' => ['present', 'array', 'max:24']],
            $bi('content.pricing.plans.*.features.*'),

            // Industries
            $bi('content.industries.title'),
            $bi('content.industries.sub'),
            ['content.industries.items' => ['present', 'array', 'max:24']],
            ['content.industries.items.*.icon' => ['nullable', 'string', 'max:8']],
            $bi('content.industries.items.*.text'),

            // FAQ (accordion)
            $bi('content.faq.title'),
            $bi('content.faq.sub'),
            ['content.faq.items' => ['present', 'array', 'max:30']],
            ['content.faq.items.*.enabled' => ['required', 'boolean']],
            $bi('content.faq.items.*.q'),
            $bi('content.faq.items.*.a'),

            // Lead form
            $bi('content.lead_form.title'),
            $bi('content.lead_form.sub'),
            $bi('content.lead_form.button'),
            $bi('content.lead_form.success'),

            // CTA band
            $bi('content.cta.title'),
            $bi('content.cta.sub'),
            $bi('content.cta.button'),
            $bi('content.cta.whatsapp_label'),

            // WhatsApp settings
            ['content.whatsapp' => ['required', 'array']],
            ['content.whatsapp.number' => ['nullable', 'string', 'max:32']],
            $bi('content.whatsapp.default_message'),
            ['content.whatsapp.floating_enabled' => ['required', 'boolean']],
            ['content.whatsapp.hero_enabled' => ['required', 'boolean']],

            // SEO (title/description/OG are bilingual { en, ar })
            ['content.seo' => ['required', 'array']],
            $bi('content.seo.title'),
            $bi('content.seo.description'),
            $bi('content.seo.og_title'),
            $bi('content.seo.og_description'),
            ['content.seo.og_image' => ['nullable', 'string', 'max:500']],

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
