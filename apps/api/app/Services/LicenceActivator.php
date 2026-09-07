<?php

namespace App\Services;

use App\Models\PosLicence;
use App\Support\LicenceKey;
use Illuminate\Support\Carbon;

/**
 * Exchanges a typed activation key for the signed licence file (POS-BE-015 §5).
 *
 * Unauthenticated: the key IS the credential. Everything this returns is a
 * document the client verifies offline against a public key compiled into its
 * binary, so nothing here needs to be trusted by the till beyond the signature.
 */
class LicenceActivator
{
    /**
     * Resolve a key to its live licence.
     *
     * Returns the licence, or a failure code from the POS-BE-019 taxonomy. The
     * codes distinguish cases the OPERATOR can act on — revoked, wrong tenant —
     * and deliberately collapse "wrong key" and "no such key" into one
     * `licence_not_found`, because that difference is an enumeration oracle and
     * is worth nothing to an honest installer.
     *
     * ## The tenant slug is optional, and that is a fix, not a loosening
     *
     * This used to demand a slug and check the licence against it. That was
     * backwards: the wizard asks for the licence FIRST precisely because the
     * licence is what *supplies* the tenant — at the licence step the till has
     * no slug to send, so "Activate online" could only ever 422 and report
     * itself to the installer as an unrecognised key. An offline licence makes
     * it worse still: there is no tenant to name.
     *
     * Dropping it costs nothing. The key is a 16-character Crockford secret
     * drawn from the CSPRNG, looked up by HMAC, and the route is throttled per
     * IP and per key — anyone holding it already holds everything the slug
     * would have guarded. When a caller DOES send one it is still enforced, so
     * an installer who points a till at the wrong customer's key is still told.
     *
     * @return array{licence: ?PosLicence, code: ?string}
     */
    public function resolve(string $key, ?string $tenantSlug = null): array
    {
        if (! LicenceKey::looksValid($key)) {
            return ['licence' => null, 'code' => 'licence_not_found'];
        }

        $hash = LicenceKey::hash($key);

        // Newest first: a renewal reuses the key on a new row, so a single key
        // legitimately matches several rows and only the live one is handed out.
        $live = PosLicence::query()
            ->with(['restaurant', 'plan'])
            ->where('key_hash', $hash)
            ->live()
            ->latest('id')
            ->first();

        if (! $live) {
            // Distinguish "revoked" from "never existed" so the wizard can say
            // something true. Both require the caller to already hold the key,
            // so this leaks nothing an attacker did not have.
            $any = PosLicence::query()->where('key_hash', $hash)->latest('id')->first();

            return [
                'licence' => null,
                'code' => $any?->revoked_at !== null ? 'licence_revoked' : 'licence_not_found',
            ];
        }

        // Checked only when offered. `clientSlug()` reads the tenant on a cloud
        // licence and the customer column on an offline one, so both kinds are
        // compared against the same thing the till will read out of the claims.
        if (($tenantSlug ?? '') !== '' && $live->clientSlug() !== $tenantSlug) {
            return ['licence' => null, 'code' => 'licence_tenant_mismatch'];
        }

        return ['licence' => $live, 'code' => null];
    }

    /**
     * Record that a terminal picked the licence up.
     *
     * First activation only — this is a "has this ever been installed?" marker
     * for the fleet list, not a counter. Seat counting is POS-BE-016 and does
     * not exist yet.
     */
    public function markActivated(PosLicence $licence, ?string $fingerprint = null): void
    {
        if ($licence->activated_at === null) {
            $licence->forceFill(['activated_at' => Carbon::now()])->save();
        }

        AuditLogger::record('pos_licence.activated', [
            'restaurant_id' => $licence->restaurant_id,
            'auditable' => $licence,
            'actor_role' => 'TERMINAL',
            'description' => "POS licence {$licence->licence_ref} activated",
            'properties' => [
                'licence_ref' => $licence->licence_ref,
                'key_last_four' => $licence->key_last_four,
                'fingerprint' => $fingerprint,
            ],
        ]);
    }

    /**
     * Record a failed attempt. Logged with the key TAIL only — never the key,
     * never the hash.
     */
    public function recordFailure(string $code, string $key, ?string $tenantSlug = null): void
    {
        AuditLogger::record('pos_licence.activation_failed', [
            'restaurant_id' => null,
            'actor_role' => 'TERMINAL',
            'description' => "POS licence activation failed: {$code}",
            'properties' => [
                'code' => $code,
                'key_last_four' => LicenceKey::lastFour($key),
                'tenant_slug' => $tenantSlug,
            ],
        ]);
    }
}
