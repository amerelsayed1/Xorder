<?php

namespace App\Http\Requests\Admin;

use App\Enums\Feature;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Issue a POS licence (POS-BE-015 §5).
 *
 * `restaurant_id` arrives in request input HERE AND ONLY HERE. This is an
 * /api/admin/* route where the actor is platform staff acting deliberately
 * across tenants — exactly like PATCH admin/restaurants/{restaurant}/subscription.
 * It is not the RestaurantScope rule being bent, and the same input on any
 * /api/dashboard/* route remains forbidden.
 */
class StoreLicenceRequest extends FormRequest
{
    /**
     * Deployment modes a licence may cover — DeploymentMode.wire values.
     *
     * The deployment model collapsed to two (owner, 2026-08-28): `cloud` and
     * `offline`. `branch_server` and `standalone` stay ACCEPTED because
     * already-signed licences carry them and the till parses both as offline
     * — but the form only offers the two current values.
     */
    public const MODES = ['cloud', 'offline', 'branch_server', 'standalone'];

    public function authorize(): bool
    {
        return $this->user()?->can('licences.manage') ?? false;
    }

    public function rules(): array
    {
        return [
            'restaurant_id' => ['required', 'integer', Rule::exists('restaurants', 'id')],
            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],

            'issued_at' => ['required', 'date'],
            'expires_at' => ['required', 'date', 'after:issued_at'],

            'grace_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'warn_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'max_terminals' => ['nullable', 'integer', 'min:1', 'max:1000'],

            // The islanded check-in window (POS-BE-022). Null = unlimited,
            // which is the correct value for cloud.
            'max_offline_days' => ['nullable', 'integer', 'min:1', 'max:365'],

            'features' => ['nullable', 'array'],
            'features.*' => ['string', Rule::in(Feature::values())],

            // Required and non-empty on purpose. An empty modes[] parses to an
            // empty set on the client, every mode then fails, and the terminal
            // reports modeNotLicensed — which reads to a cashier as a bricked
            // till with no explanation. If a licence covers everything, all
            // three must be listed explicitly.
            'modes' => ['required', 'array', 'min:1'],
            'modes.*' => ['string', Rule::in(self::MODES)],

            // Empty means every branch of the tenant.
            'branch_ids' => ['nullable', 'array'],
            'branch_ids.*' => ['integer'],

            // Empty means unpinned.
            'fingerprints' => ['nullable', 'array'],
            'fingerprints.*' => ['string', 'max:128'],

            // Commercial note. Never signed, never sent to a till.
            'notes' => ['nullable', 'string', 'max:2000'],
        ];
    }
}
