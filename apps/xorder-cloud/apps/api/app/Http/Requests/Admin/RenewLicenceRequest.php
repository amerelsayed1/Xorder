<?php

namespace App\Http\Requests\Admin;

use App\Enums\Feature;
use App\Models\PosLicence;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Renew a POS licence: a new term on a new row, superseding the old one.
 *
 * **Renewal is also how a licence is edited and upgraded.** The signed artifact
 * is the record of what the customer was sold, so nothing is changed in place:
 * every change to what is sold — plan, features, modes, terminals, users,
 * expiry, check-in window — goes through a renewal, which signs the new terms
 * and keeps the old row as the answer to "what were they entitled to in March?".
 * So this request accepts every field the licence's own kind lets an operator
 * choose, prefilled by the screen with the current values.
 *
 * Fields left out of the body are inherited from the licence being renewed, so
 * the common case — "same deal, another year" — is still two fields. A field
 * sent as null where blank means something (`max_users`, `max_offline_days`: no
 * limit) clears it; see LicenceIssuer::attributes().
 *
 * **What never changes:** the client. A renewal belongs to the same client by
 * definition; allowing the restaurant, or an offline customer's identifier, to
 * move would be a licence transfer wearing a renewal's clothes, and that is an
 * explicit new issuance. Cloud and offline licences are different kinds with
 * different rules, and a renewal cannot turn one into the other.
 */
class RenewLicenceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('licences.manage') ?? false;
    }

    /** The licence being renewed, from the route. */
    private function original(): ?PosLicence
    {
        $licence = $this->route('licence');

        return $licence instanceof PosLicence ? $licence : null;
    }

    private function isOffline(): bool
    {
        return $this->original()?->kind === PosLicence::KIND_OFFLINE;
    }

    /** `exclude_if:lifetime,true` compares against a boolean, so fold it first. */
    protected function prepareForValidation(): void
    {
        if ($this->has('lifetime')) {
            $this->merge(['lifetime' => $this->boolean('lifetime')]);
        }
    }

    public function rules(): array
    {
        $common = [
            'issued_at' => ['required', 'date'],

            // Sold outright: no expiry. Storage still writes a term, see
            // PosLicence::LIFETIME_EXPIRES_AT.
            'lifetime' => ['nullable', 'boolean'],
            'expires_at' => ['exclude_if:lifetime,true', 'required', 'date', 'after:issued_at'],

            'grace_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'warn_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'max_terminals' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'max_users' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'max_offline_days' => ['nullable', 'integer', 'min:1', 'max:365'],

            // Device binding (empty = unpinned). Changing it re-pins every
            // till: the screen warns before it is sent.
            'fingerprints' => ['nullable', 'array'],
            'fingerprints.*' => ['string', 'max:128'],

            // Commercial. Never signed, never sent to a till.
            'contact_name' => ['nullable', 'string', 'max:255'],
            'contact_email' => ['nullable', 'email', 'max:255'],
            'contact_phone' => ['nullable', 'string', 'max:32'],
            'notes' => ['nullable', 'string', 'max:2000'],

            // Default false: a six-till site should retype nothing at renewal.
            // Set when the old key must die — a leak, a departed installer.
            'rotate_key' => ['nullable', 'boolean'],
        ];

        if ($this->isOffline()) {
            // An offline customer gets the whole product, offline tills only,
            // and has no tenant: so no plan, features, modes or branches to
            // choose. What it sells is capacity. The business NAME may be
            // corrected (it is what the till prints); the identifier it
            // configures itself with is not editable here.
            return $common + [
                'customer_name' => ['nullable', 'string', 'max:255'],
            ];
        }

        return $common + [
            'plan_id' => ['nullable', 'integer', Rule::exists('plans', 'id')],

            'features' => ['nullable', 'array'],
            'features.*' => ['string', Rule::in(Feature::values())],

            'modes' => ['nullable', 'array', 'min:1', StoreLicenceRequest::oneModeRule()],
            'modes.*' => ['string', Rule::in(StoreLicenceRequest::MODES)],

            'branch_ids' => ['nullable', 'array'],
            'branch_ids.*' => ['integer'],
        ];
    }

    /**
     * A licence signed for both modes, before one mode became the rule, cannot
     * be renewed as it is: a body that leaves `modes` out would inherit both,
     * and both apps refuse such a licence. The operator picks one.
     */
    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if ($this->isOffline() || is_array($this->input('modes'))) {
                return;
            }
            if (StoreLicenceRequest::modeCount($this->original()?->modes ?? []) > 1) {
                $validator->errors()->add('modes', __('xorder.validation.licence_one_mode_renewal'));
            }
        });
    }
}
