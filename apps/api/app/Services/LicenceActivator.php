<?php

namespace App\Services;

use App\Models\PosLicence;
use App\Models\PosLicenceActivation;
use App\Support\LicenceKey;
use Illuminate\Support\Facades\DB;
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
     * Activate a device on a licence, refusing a new one when every seat is taken.
     *
     * **A local (offline) licence sells a number of devices** — `max_terminals`,
     * 1 for a single till — and this is where it is held: the devices already
     * recorded for the key are counted, and a device the platform has not seen
     * before is refused once the count has reached the number sold. A device it
     * HAS seen is always let back in, however full the licence is, because a
     * renewal reaches a till by re-fetching under the same key and refusing that
     * would lock a paying customer out of the thing they bought.
     *
     * Not applied to cloud licences. Their tills share one key by design and
     * their `max_terminals` has never been counted, so enforcing it here would
     * start refusing tills that are working today. That is a separate decision.
     *
     * The count and the insert are one locked step, so two devices arriving
     * together cannot both take the last seat.
     *
     * Honest limit: the fingerprint is reported by the till, so this stops
     * honest reuse, not a determined person spoofing it. The licence's locked
     * device list (renewal) is the stronger control, because the till itself
     * verifies it.
     *
     * @return string|null `licence_seats_full` when refused, otherwise null
     */
    public function activate(PosLicence $licence, ?string $fingerprint = null): ?string
    {
        try {
            $refused = DB::transaction(function () use ($licence, $fingerprint) {
                // Serialise per licence row, so the count below cannot go stale.
                PosLicence::query()->whereKey($licence->getKey())->lockForUpdate()->first();

                if ($this->seatsAreSold($licence)) {
                    $known = PosLicenceActivation::query()
                        ->where('key_hash', $licence->key_hash)
                        ->where('fingerprint', (string) $fingerprint)
                        ->exists();

                    if (! $known && $this->devicesUsing($licence) >= (int) $licence->max_terminals) {
                        return true;
                    }
                }

                $this->markActivated($licence, $fingerprint);

                return false;
            });
        } catch (\Throwable $e) {
            // The device ledger is bookkeeping. If it cannot be read, a paying
            // customer's till is still licensed (fail OPEN) and the failure is
            // logged; refusing here would turn a database fault into an outage.
            \Illuminate\Support\Facades\Log::warning('Licence seat check skipped', [
                'licence_ref' => $licence->licence_ref,
                'error' => $e->getMessage(),
            ]);
            $this->markActivated($licence, $fingerprint);

            return null;
        }

        if ($refused) {
            AuditLogger::record('pos_licence.activation_refused', [
                'restaurant_id' => $licence->restaurant_id,
                'auditable' => $licence,
                'actor_role' => 'TERMINAL',
                'description' => "POS licence {$licence->licence_ref}: every device seat is in use",
                'properties' => [
                    'licence_ref' => $licence->licence_ref,
                    'key_last_four' => $licence->key_last_four,
                    'seats' => $licence->max_terminals,
                    // A machine id, so only its head: enough to recognise, not to replay.
                    'fingerprint_head' => $fingerprint === null ? null : substr($fingerprint, 0, 8),
                ],
            ]);

            return 'licence_seats_full';
        }

        return null;
    }

    /** Whether this licence's device count is held at activation (local licences only). */
    public function seatsAreSold(PosLicence $licence): bool
    {
        return $licence->isOffline() && (int) $licence->max_terminals > 0;
    }

    /** How many distinct devices have used this licence's key. */
    public function devicesUsing(PosLicence $licence): int
    {
        return PosLicenceActivation::query()->where('key_hash', $licence->key_hash)->count();
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

        $this->recordDevice($licence, $fingerprint);

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
     * Remember that this device used this key, so the licence page can say so —
     * for an offline customer it is the only sign the key was ever installed.
     *
     * One row per (key, device): a repeat only moves `last_seen_at` and the
     * count. A device that reported no fingerprint is the single '' row. This
     * must never break an activation, so a failure here is logged and swallowed:
     * a till that cannot be licensed because a bookkeeping table is unhappy is a
     * worse outcome than a missing line on a page.
     */
    private function recordDevice(PosLicence $licence, ?string $fingerprint): void
    {
        try {
            $now = Carbon::now();
            $device = PosLicenceActivation::query()->firstOrNew([
                'key_hash' => $licence->key_hash,
                'fingerprint' => (string) $fingerprint,
            ]);

            if ($device->exists) {
                $device->forceFill(['last_seen_at' => $now, 'times' => $device->times + 1])->save();
            } else {
                $device->forceFill(['first_seen_at' => $now, 'last_seen_at' => $now, 'times' => 1])->save();
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Licence activation device not recorded', [
                'licence_ref' => $licence->licence_ref,
                'error' => $e->getMessage(),
            ]);
        }
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
