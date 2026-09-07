<?php

namespace App\Http\Requests\Pos;

use App\Http\Requests\Admin\StoreLicenceRequest;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * A till exchanging a typed key for its signed licence.
 *
 * Unauthenticated — the key IS the credential — so everything here is hostile
 * input and the route is throttled per IP and per key.
 */
class ActivateLicenceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'key' => ['required', 'string', 'max:64'],

            // OPTIONAL, and deliberately so. The till asks for the licence
            // before it asks for anything else — the licence is what tells it
            // which tenant it serves — so at the moment this call is made there
            // is usually no slug to send. Requiring one made "Activate online"
            // impossible to satisfy from the wizard's first screen, and it is
            // meaningless for an offline customer who is no tenant at all.
            // When one IS sent it is still enforced; see LicenceActivator.
            'tenant_slug' => ['nullable', 'string', 'max:255'],

            // Recorded for the fleet view, not enforced here. The client is the
            // thing that decides whether a pinned licence matches its machine,
            // because it is the only party that can do so offline.
            'deployment_mode' => ['nullable', 'string', Rule::in(StoreLicenceRequest::MODES)],
            'fingerprint' => ['nullable', 'string', 'max:128'],
            'terminal_id' => ['nullable', 'string', 'max:64'],
        ];
    }
}
