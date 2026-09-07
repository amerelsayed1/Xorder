<?php

namespace App\Http\Requests\Admin;

use App\Enums\Feature;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Issue a POS licence to a customer who is NOT a tenant of this platform.
 *
 * The counterpart to StoreLicenceRequest, and the difference is the whole
 * point: that one takes a `restaurant_id`, this one takes a customer. Nothing
 * here creates a tenant, an admin user, a subscription or an entitlement set,
 * because an on-premises restaurant runs its own database and none of those
 * records would ever describe anything true.
 *
 * What the platform keeps is the licence-management minimum — who owns it,
 * what they bought, when it lapses, whether it is revoked. There is no tenant
 * for products, orders, branches or sales to hang off, which is the structural
 * form of "no business data is synced".
 */
class StoreOfflineLicenceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('licences.manage') ?? false;
    }

    /**
     * Fold `lifetime` to a real boolean before anything reads it.
     *
     * `exclude_if:lifetime,true` compares against a boolean, and a form that
     * posts "1" or "on" would otherwise fall through to demanding an expiry
     * date for a licence that has none.
     */
    protected function prepareForValidation(): void
    {
        $this->merge(['lifetime' => $this->boolean('lifetime')]);
    }

    public function rules(): array
    {
        return [
            // The business. Signed into the `tenant_name` claim, so it is what
            // the till prints on its own screens and receipts.
            'customer_name' => ['required', 'string', 'max:255'],

            // Signed into `tenant_slug` — the identifier the till configures
            // itself with. Must not collide with a hosted tenant's slug: two
            // clients answering to one identifier is a support call nobody can
            // resolve over the phone.
            'customer_slug' => [
                'required', 'string', 'max:64',
                'regex:/^[a-z0-9]+(-[a-z0-9]+)*$/',
                Rule::unique('restaurants', 'slug'),
            ],

            // Who to call. Commercial contact only — never signed, never sent
            // to a till, and deliberately NOT a user account: an offline
            // customer has no login here and must not acquire one.
            'contact_name' => ['nullable', 'string', 'max:255'],
            'contact_email' => ['nullable', 'email', 'max:255'],
            'contact_phone' => ['nullable', 'string', 'max:32'],

            'issued_at' => ['required', 'date'],

            // Sold outright. Storage still writes a term — see
            // PosLicence::LIFETIME_EXPIRES_AT for why a null date would not
            // parse on tills already in the field.
            'lifetime' => ['nullable', 'boolean'],
            'expires_at' => ['exclude_if:lifetime,true', 'required', 'date', 'after:issued_at'],

            'grace_days' => ['nullable', 'integer', 'min:0', 'max:365'],
            'warn_days' => ['nullable', 'integer', 'min:0', 'max:365'],

            // WHAT AN OFFLINE LICENCE ACTUALLY SELLS — capacity, not features.
            //
            // How many tills the customer bought. Also what decides, on the
            // till, whether the database may live on another machine.
            'max_terminals' => ['nullable', 'integer', 'min:1', 'max:1000'],

            // And how many people may hold an account on them. Null =
            // unlimited. Unlike the terminal count this is enforced on the
            // till, because every staff row is in the one database it can see.
            'max_users' => ['nullable', 'integer', 'min:1', 'max:1000'],

            // The islanded check-in window (POS-BE-022). Null = never has to
            // come back, which is the honest answer for a site with no
            // internet at all.
            'max_offline_days' => ['nullable', 'integer', 'min:1', 'max:365'],

            // Empty means unpinned.
            'fingerprints' => ['nullable', 'array'],
            'fingerprints.*' => ['string', 'max:128'],

            // Commercial note. Never signed, never sent to a till.
            'notes' => ['nullable', 'string', 'max:2000'],
        ];
    }

    /**
     * The claims an offline licence is not permitted to choose.
     *
     * **`features` is every feature there is, always.** An on-premises customer
     * gets the whole product. Feature gating only means something where the
     * platform can enforce it, and on a machine we do not run it is a promise
     * we cannot keep — the till verifies its own licence and could be patched
     * by anyone who cared to. So what is sold here is CAPACITY instead:
     * `max_terminals` (devices) and `max_users` (people). That is also why this
     * form has no plan picker — a plan exists to select features, and there is
     * nothing here to select.
     *
     * `modes` is forced to offline-only because cloud mode means syncing to a
     * tenant, and this customer has none — a licence permitting it would send
     * the till hunting for a tenant that does not exist. `branch_ids` is empty
     * for the same reason: their branches live in their own database, and the
     * ids here index a table that knows nothing about them.
     *
     * Forced rather than validated, so no request body can argue.
     *
     * @return array<string,mixed>
     */
    public function licenceData(): array
    {
        // array_merge, not `+`: these must WIN over anything validated, not
        // merely fill a gap the body left.
        return array_merge($this->validated(), [
            'features' => Feature::values(),
            // The DeploymentMode wire value — which happens to read the same as
            // the licence kind, and is not the same vocabulary. Spelled out
            // rather than borrowing PosLicence::KIND_OFFLINE, so that renaming
            // one can never silently change the other.
            'modes' => ['offline'],
            'branch_ids' => [],
            // No plan: see above. Kept explicit so a renewal cannot inherit one
            // from somewhere and quietly start gating features.
            'plan_id' => null,
        ]);
    }

    public function messages(): array
    {
        return [
            'customer_slug.regex' => __('xorder.validation.slug_regex'),
            'customer_slug.unique' => __('xorder.validation.slug_taken_by_tenant'),
        ];
    }
}
