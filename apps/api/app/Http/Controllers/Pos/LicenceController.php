<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\ActivateLicenceRequest;
use App\Models\PosLicence;
use App\Services\LicenceActivator;
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
     * The response is the bare three-key file and nothing else. LicenseFile
     * .tryParse ignores extra keys, but keeping it minimal is what makes "the
     * download and the API response are the same document" true rather than
     * merely intended.
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

        $this->activator->markActivated($licence, $request->input('fingerprint'));

        return response()->json($licence->file());
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
