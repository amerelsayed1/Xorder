<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\ActivateLicenceRequest;
use App\Http\Requests\Pos\LicenceCheckRequest;
use App\Models\PosLicence;
use App\Models\PosTerminal;
use App\Services\LicenceActivator;
use App\Services\LicenceIssuer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The till's half of POS-BE-015.
 */
class LicenceController extends Controller
{
    public function __construct(private readonly LicenceActivator $activator) {}

    /**
     * Exchange a typed key for the signed licence file.
     *
     * Unauthenticated: the key IS the credential. Throttled per IP and per key.
     *
     * IDEMPOTENT BY CONSTRUCTION. Signing happened once, at issuance, and the
     * artifact is stored — so re-activating the same key returns byte-identical
     * bytes without re-signing, and those bytes are the same ones the .xlic
     * download produces. Nothing here can make the two paths drift.
     *
     * The response is the three-key file plus `enforcement` (R2, owner
     * decision 2026-10-07): an islanded till may never call bootstrap, and
     * this is the one reply it is sure to get. LicenseFile.tryParse ignores
     * extra keys, and the three it reads are still byte-identical to the
     * download, which is the property that matters.
     *
     * EnsureSubscriptionAllowsWrites deliberately does NOT apply: a lapsed
     * subscription must not stop a till installing a licence the customer
     * already paid for. That converts a collections problem into an outage.
     */
    public function activate(ActivateLicenceRequest $request): JsonResponse
    {
        $key = (string) $request->input('key');
        // Null, not '', when absent: the activator treats an empty slug as "not
        // offered" and skips the check rather than comparing against nothing.
        $slug = $request->filled('tenant_slug') ? (string) $request->input('tenant_slug') : null;

        ['licence' => $licence, 'code' => $code] = $this->activator->resolve($key, $slug);

        if ($licence === null) {
            $this->activator->recordFailure($code, $key, $slug);

            return response()->json([
                'message' => __('xorder.errors.'.$code),
                'code' => $code,
            ], $code === 'licence_revoked' ? 403 : 404);
        }

        // A local licence sells a number of devices; a new one is refused once
        // they are all in use. 409, not 403: the key is fine and nothing about
        // it is revoked, so a till must not say "revoked". `code` is what the
        // till reads.
        if ($this->activator->activate($licence, $request->input('fingerprint')) === 'licence_seats_full') {
            return response()->json([
                'message' => __('xorder.errors.licence_seats_full', ['seats' => (int) $licence->max_terminals]),
                'code' => 'licence_seats_full',
                'seats' => (int) $licence->max_terminals,
            ], 409);
        }

        // The signed file, plus two things that are not part of it and that
        // LicenseFile.tryParse is free to ignore: where this till takes its
        // verdict from (R2), and the public key this platform signs with, so a
        // DEVELOPMENT build of the till can read the file without the key
        // being carried over by hand — see LicenceIssuer::configuredPublicKey.
        return response()->json($licence->file() + array_filter([
            'enforcement' => $licence->enforcement ?? PosLicence::ENFORCEMENT_ONLINE,
            'issuer_public_key' => LicenceIssuer::configuredPublicKey(),
        ]));
    }

    /**
     * The key this platform signs licences with, and its id.
     *
     * Unauthenticated and unthrottled beyond the global limit: a public key is
     * public by definition — it ships inside every customer's binary — and
     * nothing here is secret. What it buys is a RELEASE build that carries the
     * right key: the installer builds (`windows-installer.yml`,
     * `package_macos.sh`) take `XORDER_LICENSE_PUBLIC_KEY_B64` and
     * `XORDER_LICENSE_KEY_ID`, and until 16 Oct 2026 the only way to learn
     * them was to decode the private key by hand on the server. Nobody had, so
     * no release build had ever been able to read a production licence
     * (audit S1-2). Now the release pipeline reads them from here.
     *
     * 503 when no signing key is configured: a platform that cannot sign has
     * nothing to publish, and an empty key would be built into a binary.
     */
    public function issuer(): JsonResponse
    {
        $publicKey = LicenceIssuer::configuredPublicKey();

        if ($publicKey === null) {
            return response()->json([
                'message' => __('xorder.errors.licence_issuer_unconfigured'),
                'code' => 'licence_issuer_unconfigured',
            ], 503);
        }

        return response()->json([
            'key_id' => (string) config('licence.key_id', 'v1'),
            'public_key' => $publicKey,
            'algorithm' => 'ed25519',
        ]);
    }

    /**
     * The online verdict for a connected till (R2, POS-BE-031).
     *
     * Asked on the splash screen and before each new shift. `status` is the
     * one field the till acts on; the rest says why and for how long. Device
     * credential, no-feature, like `current` and the heartbeat: a till whose
     * pos flag lapsed must still hear why. The restaurant is the terminal's.
     *
     * Read-only as far as the licence goes. What the till reports, and when it
     * last asked, is written to the terminal quietly, as the heartbeat writes
     * its telemetry — never an audited edit.
     *
     * This is commercial hygiene, not security: the answer is unsigned, over
     * TLS, and every money write is still gated server-side on feature:pos.
     */
    public function check(LicenceCheckRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        $licence = PosLicence::query()
            ->where('restaurant_id', $terminal->restaurant_id)
            ->live()
            ->latest('id')
            ->first();

        $data = $request->validated();
        $terminal->forceFill([
            'last_licence_check_at' => now(),
            'licence_id' => $licence?->id,
            'app_version' => $data['app_version'] ?? $terminal->app_version,
            'reported_licence_expires_at' => $data['licence_expires_at'] ?? $terminal->reported_licence_expires_at,
        ])->saveQuietly();

        if (! $licence) {
            return response()->json([
                'message' => __('xorder.errors.licence_none_for_terminal'),
                'code' => 'licence_not_found',
            ], 404);
        }

        $status = $licence->verdict();

        return response()->json([
            'status' => $status,
            'licence_ref' => $licence->licence_ref,
            'starts_at' => $licence->issued_at?->toIso8601String(),
            'expires_at' => $licence->lifetime ? null : $licence->expires_at?->toIso8601String(),
            'lifetime' => (bool) $licence->lifetime,
            'grace_days' => $licence->grace_days,
            'warn_days' => $licence->warn_days,
            'max_terminals' => $licence->max_terminals,
            'max_users' => $licence->max_users,
            'features' => $licence->features ?? [],
            'enforcement' => $licence->enforcement ?? PosLicence::ENFORCEMENT_ONLINE,
            'message' => match ($status) {
                'suspended' => $licence->suspended_reason ?: __('xorder.errors.licence_suspended'),
                'expired' => __('xorder.errors.licence_expired'),
                'not_yet_valid' => __('xorder.errors.licence_not_yet_valid'),
                default => null,
            },
            'server_time' => now()->toIso8601String(),
            'grace_policy' => [
                'cache_seconds' => (int) config('licence.check_cache_seconds', 259200),
            ],
        ]);
    }

    /**
     * The newest live licence for the authenticated terminal's tenant.
     *
     * Called at boot and before each shift opens, so a renewal applied on the
     * platform reaches the till without anyone typing anything.
     *
     * Gated by the DEVICE credential (POS-BE-011/023 — the provisional jwt
     * gating this shipped with was tightened when those landed, as the
     * contract said it would be). The restaurant is the terminal's own,
     * never request input. Runs in no-feature mode: a till whose pos flag
     * lapsed must still be able to read its licence — that is how it learns
     * why nothing else works.
     */
    public function current(Request $request): JsonResponse
    {
        $restaurantId = $request->attributes->get('pos_terminal')?->restaurant_id;

        if (! $restaurantId) {
            return response()->json(['message' => __('xorder.errors.licence_not_found'), 'code' => 'licence_not_found'], 404);
        }

        $licence = PosLicence::query()
            ->where('restaurant_id', $restaurantId)
            ->live()
            ->latest('id')
            ->first();

        if (! $licence) {
            return response()->json(['message' => __('xorder.errors.licence_not_found'), 'code' => 'licence_not_found'], 404);
        }

        return response()->json($licence->file());
    }
}
