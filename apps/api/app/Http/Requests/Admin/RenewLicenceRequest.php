<?php

namespace App\Http\Requests\Admin;

use App\Enums\Feature;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Renew a POS licence: a new term on a new row, superseding the old one.
 *
 * Everything except the dates is optional and inherited from the licence being
 * renewed, so the common case — "same deal, another year" — is two fields.
 *
 * The restaurant is NOT accepted here. A renewal belongs to the same client by
 * definition; allowing it to move would be a licence transfer wearing a
 * renewal's clothes, and that should be an explicit new issuance.
 */
class RenewLicenceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('licences.manage') ?? false;
    }

    public function rules(): array
    {
        return [
            'issued_at' => ['required', 'date'],
            'expires_at' => ['required', 'date', 'after:issued_at'],

            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],
            'grace_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'warn_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'max_terminals' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'max_offline_days' => ['nullable', 'integer', 'min:1', 'max:365'],

            'features' => ['nullable', 'array'],
            'features.*' => ['string', Rule::in(Feature::values())],

            'modes' => ['nullable', 'array', 'min:1'],
            'modes.*' => ['string', Rule::in(StoreLicenceRequest::MODES)],

            'branch_ids' => ['nullable', 'array'],
            'branch_ids.*' => ['integer'],

            'fingerprints' => ['nullable', 'array'],
            'fingerprints.*' => ['string', 'max:128'],

            'notes' => ['nullable', 'string', 'max:2000'],

            // Default false: a six-till site should retype nothing at renewal.
            // Set when the old key must die — a leak, a departed installer.
            'rotate_key' => ['nullable', 'boolean'],
        ];
    }
}
