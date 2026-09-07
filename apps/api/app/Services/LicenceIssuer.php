<?php

namespace App\Services;

use App\Models\PosLicence;
use App\Models\Restaurant;
use App\Models\User;
use App\Support\LicenceKey;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Mints, renews and revokes POS licences (POS-BE-015).
 *
 * ## What is signed, exactly
 *
 * `payload` is base64url of the UTF-8 claims JSON, and `signature` is Ed25519
 * over the DECODED payload bytes — not over the base64 string, and not over a
 * canonical re-serialisation. That is what the client does
 * (LicenseVerifier.verifySignature base64url-decodes and passes those bytes as
 * the message), so the issuer must build the JSON once, keep the byte string,
 * sign those bytes, and encode those same bytes. A re-serialisation that
 * reorders keys or changes whitespace produces a file that will not verify.
 *
 * There is no `alg` field, ever. The algorithm is fixed in the client and
 * cannot be selected by the file; that absence is the whole reason this is not
 * a JWT, and adding the field would reintroduce the "alg: none" bug class the
 * format exists to avoid.
 *
 * ## Signing happens once
 *
 * At issuance, never at activation. The artifact is stored verbatim, so
 * re-activating a key returns byte-identical bytes and the downloaded .xlic and
 * the activation response are provably the same document.
 */
class LicenceIssuer
{
    /**
     * Issue a brand-new licence and return it alongside the plaintext key.
     *
     * The key is returned exactly once — the row keeps only its HMAC — so the
     * caller is responsible for showing it to the operator before it is gone.
     *
     * `$restaurant` is null for an OFFLINE licence: a customer who is not a
     * tenant of this platform and must not become one. Their identity comes
     * from `$data` (`customer_name`, `customer_slug`) and is written with
     * forceFill alongside the tenant key, because on that row those columns are
     * what gets signed into the `tenant_slug` and `tenant_name` claims.
     *
     * @param  array<string,mixed>  $data
     * @return array{licence: PosLicence, key: string}
     */
    public function issue(?Restaurant $restaurant, array $data, ?User $actor = null): array
    {
        $key = LicenceKey::generate();

        $licence = DB::transaction(function () use ($restaurant, $data, $actor, $key) {
            $licence = new PosLicence($this->attributes($data));

            $licence->forceFill([
                'restaurant_id' => $restaurant?->id,
                'kind' => $restaurant === null ? PosLicence::KIND_OFFLINE : PosLicence::KIND_CLOUD,
                'customer_name' => $restaurant === null ? ($data['customer_name'] ?? null) : null,
                'customer_slug' => $restaurant === null ? ($data['customer_slug'] ?? null) : null,
                'key_hash' => LicenceKey::hash($key),
                'key_last_four' => LicenceKey::lastFour($key),
                'created_by_id' => $actor?->id,
                // Placeholder: the real reference needs the id, and the id needs
                // the insert. Never escapes the transaction.
                'licence_ref' => 'LIC-PENDING-'.Str::random(20),
                'payload' => '',
                'signature' => '',
                'key_id' => (string) config('licence.key_id', 'v1'),
            ])->save();

            return $this->seal($licence->fresh(['restaurant', 'plan']));
        });

        AuditLogger::record('pos_licence.issued', [
            // Explicitly null for an offline licence: there is no tenant this
            // entry belongs to, and AuditLogger honours a null that is present
            // rather than inferring one from the actor.
            'restaurant_id' => $restaurant?->id,
            'actor' => $actor,
            'auditable' => $licence,
            'description' => "Issued POS licence {$licence->licence_ref} to {$licence->clientName()}",
            'properties' => $this->auditProperties($licence),
        ]);

        return ['licence' => $licence, 'key' => $key];
    }

    /**
     * Renew a licence: a NEW row with a new term, superseding the old one.
     *
     * The term is not mutated in place, because the signed artifact is the
     * record of what the customer was actually sold and overwriting it erases
     * that. It also means "what were they entitled to in March?" has an answer.
     *
     * The activation key is reused by default, so a six-till site retypes
     * nothing at renewal — the tills re-fetch and receive the new term. Pass
     * `rotate_key` when the old key must die (a leak, a departed installer), in
     * which case the new key is returned and the old one stops resolving.
     *
     * @param  array<string,mixed>  $data
     * @return array{licence: PosLicence, key: ?string}
     */
    public function renew(PosLicence $original, array $data, ?User $actor = null): array
    {
        $rotate = (bool) ($data['rotate_key'] ?? false);
        $key = $rotate ? LicenceKey::generate() : null;

        $licence = DB::transaction(function () use ($original, $data, $actor, $key) {
            $renewal = new PosLicence($this->attributes($data, $original));

            $renewal->forceFill([
                // The client never changes on a renewal, of either kind. A
                // renewal that could re-point a licence at another customer
                // would be an edit wearing a new term's clothes.
                'restaurant_id' => $original->restaurant_id,
                'kind' => $original->kind,
                'customer_name' => $original->customer_name,
                'customer_slug' => $original->customer_slug,
                'key_hash' => $key ? LicenceKey::hash($key) : $original->key_hash,
                'key_last_four' => $key ? LicenceKey::lastFour($key) : $original->key_last_four,
                'created_by_id' => $actor?->id,
                'licence_ref' => 'LIC-PENDING-'.Str::random(20),
                'payload' => '',
                'signature' => '',
                'key_id' => (string) config('licence.key_id', 'v1'),
            ])->save();

            $renewal = $this->seal($renewal->fresh(['restaurant', 'plan']));

            $original->forceFill(['superseded_by_id' => $renewal->id])->save();

            return $renewal;
        });

        AuditLogger::record('pos_licence.renewed', [
            'restaurant_id' => $licence->restaurant_id,
            'actor' => $actor,
            'auditable' => $licence,
            'description' => "Renewed POS licence {$original->licence_ref} as {$licence->licence_ref}",
            'properties' => $this->auditProperties($licence) + [
                'superseded' => $original->licence_ref,
                'key_rotated' => $key !== null,
            ],
        ]);

        return ['licence' => $licence, 'key' => $key];
    }

    /**
     * Revoke a licence.
     *
     * This is weak by design and the UI must not imply otherwise: a licence
     * verified entirely offline cannot be recalled. Revocation bites only when
     * the till next reaches /current or /bootstrap, and an islanded till keeps
     * trading until its max_offline_days window closes. Real enforcement stays
     * server-side on the feature:pos entitlement.
     */
    public function revoke(PosLicence $licence, ?string $reason, ?User $actor = null): PosLicence
    {
        $licence->forceFill([
            'revoked_at' => Carbon::now(),
            'revoked_reason' => $reason,
        ])->save();

        AuditLogger::record('pos_licence.revoked', [
            'restaurant_id' => $licence->restaurant_id,
            'actor' => $actor,
            'auditable' => $licence,
            'description' => "Revoked POS licence {$licence->licence_ref}",
            'properties' => ['licence_ref' => $licence->licence_ref, 'reason' => $reason],
        ]);

        return $licence->fresh(['restaurant', 'plan']);
    }

    /**
     * Give the row its final reference, mint the signed artifact, store it.
     *
     * Split out so issue() and renew() cannot drift: both seal the same way.
     */
    private function seal(PosLicence $licence): PosLicence
    {
        $ref = sprintf('LIC-%s-%04d', $licence->issued_at->format('Y'), $licence->id);

        $licence->forceFill(['licence_ref' => $ref]);

        $file = $this->mint($licence);

        $licence->forceFill([
            'payload' => $file['payload'],
            'signature' => $file['signature'],
            'key_id' => $file['key_id'],
        ])->save();

        return $licence;
    }

    /**
     * Build the claims, sign them, and return the distributable file.
     *
     * @return array{payload: string, signature: string, key_id: string}
     */
    public function mint(PosLicence $licence): array
    {
        $claims = $this->claims($licence);

        // Build the bytes ONCE and sign those exact bytes. Do not re-encode
        // from a decoded structure anywhere downstream.
        $json = json_encode($claims, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);

        $signature = sodium_crypto_sign_detached($json, $this->signingKey());

        return [
            'payload' => $this->base64url($json),
            'signature' => $this->base64url($signature),
            'key_id' => (string) config('licence.key_id', 'v1'),
        ];
    }

    /**
     * The signed claims.
     *
     * The keys use the AMERICAN spelling `license_id` while every identifier in
     * both codebases says `licence`. That is not a typo awaiting a fix — it is
     * what installed tills parse (LicenseClaims.fromJson), and changing it would
     * break every licence already issued.
     *
     * @return array<string,mixed>
     */
    public function claims(PosLicence $licence): array
    {
        return [
            'license_id' => $licence->licence_ref,
            // Resolved through the licence, not through the tenant: an offline
            // licence has no tenant, and these two claims are how the till
            // learns whose it is. Byte-identical output for a cloud licence —
            // the same name_en → name_ar → slug fallback as before.
            'tenant_slug' => $licence->clientSlug(),
            'tenant_name' => $licence->clientName(),
            'issued_at' => $licence->issued_at->toIso8601String(),
            'expires_at' => $licence->expires_at->toIso8601String(),
            'grace_days' => (int) $licence->grace_days,
            'warn_days' => (int) $licence->warn_days,
            'max_terminals' => (int) $licence->max_terminals,
            // The other half of what an on-premises customer buys. Enforceable
            // on the till in a way max_terminals is not: every staff row is in
            // the one database that terminal can already see.
            'max_users' => $licence->max_users !== null ? (int) $licence->max_users : null,
            'max_offline_days' => $licence->max_offline_days !== null ? (int) $licence->max_offline_days : null,
            'features' => array_values($licence->features ?? []),
            // DeploymentMode.wire values — cloud | branch_server | standalone.
            // Never emitted empty: an empty array parses to an empty set on the
            // client, every mode then fails, and the terminal reports
            // modeNotLicensed, which reads to a cashier as a bricked till.
            'modes' => array_values($licence->modes ?? []),
            'branch_ids' => array_values(array_map('intval', $licence->branch_ids ?? [])),
            'fingerprints' => array_values($licence->fingerprints ?? []),
            'plan' => $licence->plan?->name,
        ];
    }

    /**
     * Fillable attributes for a new row, with an original to inherit from on
     * renewal so a renewal that only moves the dates keeps its scope.
     *
     * @param  array<string,mixed>  $data
     * @return array<string,mixed>
     */
    private function attributes(array $data, ?PosLicence $original = null): array
    {
        $defaults = (array) config('licence.defaults', []);

        $inherit = fn (string $field, mixed $fallback) => $data[$field]
            ?? $original?->{$field}
            ?? $fallback;

        // Sold outright. The stored term becomes the sentinel, so every date
        // comparison downstream — grace, warning, the till's own expiry check —
        // keeps working on a licence that simply never arrives at its end. See
        // PosLicence::LIFETIME_EXPIRES_AT for why this is not a null.
        $lifetime = (bool) ($data['lifetime'] ?? $original?->lifetime ?? false);

        return [
            'plan_id' => $inherit('plan_id', null),
            'issued_at' => Carbon::parse($inherit('issued_at', 'now')),
            'expires_at' => $lifetime
                ? Carbon::parse(PosLicence::LIFETIME_EXPIRES_AT)
                : Carbon::parse($inherit('expires_at', null)),
            'lifetime' => $lifetime,
            'contact_name' => $inherit('contact_name', null),
            'contact_email' => $inherit('contact_email', null),
            'contact_phone' => $inherit('contact_phone', null),
            'grace_days' => $inherit('grace_days', $defaults['grace_days'] ?? 14),
            'warn_days' => $inherit('warn_days', $defaults['warn_days'] ?? 30),
            'max_terminals' => $inherit('max_terminals', $defaults['max_terminals'] ?? 1),
            // Null = unlimited. Correct for cloud, where the platform counts
            // staff against the plan server-side instead.
            'max_users' => $data['max_users'] ?? $original?->max_users,
            'max_offline_days' => $data['max_offline_days'] ?? $original?->max_offline_days,
            'features' => array_values($inherit('features', [])),
            'modes' => array_values($inherit('modes', ['cloud'])),
            'branch_ids' => array_values($inherit('branch_ids', [])),
            'fingerprints' => array_values($inherit('fingerprints', [])),
            'notes' => $data['notes'] ?? $original?->notes,
        ];
    }

    /** @return array<string,mixed> */
    private function auditProperties(PosLicence $licence): array
    {
        // licence_ref and the key tail only — never the key, never the hash.
        return [
            'licence_ref' => $licence->licence_ref,
            'key_last_four' => $licence->key_last_four,
            'expires_at' => $licence->lifetime ? 'lifetime' : $licence->expires_at->toIso8601String(),
            'max_terminals' => $licence->max_terminals,
            'max_users' => $licence->max_users,
            'modes' => $licence->modes,
        ];
    }

    private function signingKey(): string
    {
        $configured = (string) config('licence.signing_key');

        if ($configured === '') {
            throw new RuntimeException(
                'LICENCE_SIGNING_KEY is not set. Run `php artisan licence:keygen` and add it to .env.'
            );
        }

        $secret = base64_decode($configured, true);

        if ($secret === false || strlen($secret) !== SODIUM_CRYPTO_SIGN_SECRETKEYBYTES) {
            throw new RuntimeException(
                'LICENCE_SIGNING_KEY is not a base64 Ed25519 secret key of '
                .SODIUM_CRYPTO_SIGN_SECRETKEYBYTES.' bytes.'
            );
        }

        return $secret;
    }

    private function base64url(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }
}
