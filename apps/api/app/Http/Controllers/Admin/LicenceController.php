<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\RenewLicenceRequest;
use App\Http\Requests\Admin\StoreLicenceRequest;
use App\Http\Requests\Admin\StoreOfflineLicenceRequest;
use App\Http\Resources\PosLicenceResource;
use App\Http\Resources\PosTerminalResource;
use App\Models\PosLicence;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use App\Services\LicenceIssuer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Super Admin issuance of POS licences (POS-BE-015 §4).
 *
 * These reads are deliberately CROSS-TENANT — the same posture the fleet views
 * in POS-BE-022 need. PosLicence carries no RestaurantScope, so that is
 * explicit here rather than incidental: every query below names the restaurant
 * it wants, or deliberately names none.
 */
class LicenceController extends Controller
{
    public function __construct(private readonly LicenceIssuer $issuer) {}

    public function index(Request $request): JsonResponse
    {
        $licences = PosLicence::query()
            ->with(['restaurant', 'plan'])
            ->when($request->integer('restaurant_id'), fn ($q, $id) => $q->where('restaurant_id', $id))
            // Cloud and offline licences share one list — an operator asking
            // "whose licence expires next?" should not have to ask it twice.
            ->when(
                in_array($request->string('kind')->toString(), [PosLicence::KIND_CLOUD, PosLicence::KIND_OFFLINE], true),
                fn ($q) => $q->where('kind', $request->string('kind')->toString()),
            )
            // The operator's status (R2) — "who is suspended?" is a list.
            ->when(
                in_array($request->string('status')->toString(), [PosLicence::STATUS_ACTIVE, PosLicence::STATUS_SUSPENDED, PosLicence::STATUS_EXPIRED], true),
                fn ($q) => $q->where('status', $request->string('status')->toString()),
            )
            ->when($request->string('search')->toString() !== '', function ($q) use ($request) {
                $term = '%'.$request->string('search')->toString().'%';

                $q->where(fn ($w) => $w
                    ->where('licence_ref', 'like', $term)
                    ->orWhere('customer_name', 'like', $term)
                    ->orWhere('customer_slug', 'like', $term)
                    ->orWhereHas('restaurant', fn ($r) => $r
                        ->where('slug', 'like', $term)
                        ->orWhere('name_en', 'like', $term)
                        ->orWhere('name_ar', 'like', $term)));
            })
            ->when($request->boolean('live_only'), fn ($q) => $q->live())
            ->when(
                $request->integer('expiring_within_days'),
                fn ($q, $days) => $q->live()->whereBetween('expires_at', [now(), now()->addDays($days)]),
            )
            ->latest('id')
            ->paginate($request->integer('per_page', 25));

        return PosLicenceResource::collection($licences)->response();
    }

    /**
     * Issue a licence.
     *
     * The activation key appears in THIS ONE RESPONSE and never again — the row
     * keeps only its HMAC. Same discipline as a personal access token: the
     * dashboard must force the operator to copy it before the modal closes.
     */
    public function store(StoreLicenceRequest $request): JsonResponse
    {
        $restaurant = Restaurant::findOrFail($request->integer('restaurant_id'));

        $result = $this->issuer->issue($restaurant, $request->validated(), $request->user());

        return response()->json([
            'data' => PosLicenceResource::make($result['licence']),
            'activation_key' => $result['key'],
            'file' => $result['licence']->file(),
            'message' => __('xorder.messages.licence_issued'),
        ], 201);
    }

    /**
     * Issue a licence to a customer who is NOT a tenant here.
     *
     * A separate endpoint rather than a `kind` flag on store(), because the two
     * take genuinely different input — one names a restaurant, the other
     * describes a business we do not host — and a single request class that
     * validated both would have to make every field of each conditional on the
     * other. From here down the paths converge: one issuer, one signing key,
     * one renew, one revoke, one download.
     *
     * NOTHING ELSE IS CREATED. No tenant, no admin user, no subscription, no
     * entitlement row. That is the feature, not an omission.
     */
    public function storeOffline(StoreOfflineLicenceRequest $request): JsonResponse
    {
        $result = $this->issuer->issue(null, $request->licenceData(), $request->user());

        return response()->json([
            'data' => PosLicenceResource::make($result['licence']),
            'activation_key' => $result['key'],
            'file' => $result['licence']->file(),
            'message' => __('xorder.messages.licence_issued'),
        ], 201);
    }

    public function show(PosLicence $licence): JsonResponse
    {
        // `restaurant` is null on an offline licence; loading it is still
        // correct — the resource distinguishes "not loaded" from "loaded null".
        $licence->load(['restaurant', 'plan']);

        return response()->json([
            'data' => PosLicenceResource::make($licence),
            // The decoded claims, so an operator can see exactly what the till
            // will read without base64-decoding anything by hand.
            'claims' => $this->issuer->claims($licence),
        ]);
    }

    /**
     * The activation key, again.
     *
     * It used to be shown once, at issuance, and never again — the row kept
     * only an HMAC. A key not written down at that moment was gone, and the
     * only way forward was a renewal with `rotate_key`, which this platform's
     * first customer did three times in an afternoon (owner decision, 16 Oct
     * 2026). The key is now kept encrypted and handed back HERE, to a Super
     * Admin, with an audit row for every read. Licences issued before it was
     * kept answer 404 with a code the page turns into a sentence.
     */
    public function key(Request $request, PosLicence $licence): JsonResponse
    {
        $key = $licence->activationKey();

        if ($key === null) {
            return response()->json([
                'message' => __('xorder.messages.licence_key_not_kept'),
                'code' => 'licence_key_not_kept',
            ], 404);
        }

        AuditLogger::record('pos_licence.key_revealed', [
            'restaurant_id' => $licence->restaurant_id,
            'actor' => $request->user(),
            'auditable' => $licence,
            'description' => "Activation key of POS licence {$licence->licence_ref} copied",
            // The tail only, as every licence audit row: never the key.
            'properties' => ['licence_ref' => $licence->licence_ref, 'key_last_four' => $licence->key_last_four],
        ]);

        return response()->json([
            'licence_ref' => $licence->licence_ref,
            'activation_key' => $key,
        ]);
    }

    /**
     * Renew: a new row with a new term, superseding this one.
     *
     * The activation key is unchanged unless `rotate_key` was set, so the
     * response carries a key only in that case; the existing one is a GET on
     * `licences/{licence}/key` away.
     */
    public function renew(RenewLicenceRequest $request, PosLicence $licence): JsonResponse
    {
        $result = $this->issuer->renew($licence, $request->validated(), $request->user());

        return response()->json([
            'data' => PosLicenceResource::make($result['licence']),
            'activation_key' => $result['key'],
            'key_unchanged' => $result['key'] === null,
            'file' => $result['licence']->file(),
            'message' => __('xorder.messages.licence_renewed'),
        ], 201);
    }

    /**
     * Revoke.
     *
     * Weak by design, and the UI must not imply otherwise: a licence verified
     * entirely offline cannot be recalled. This bites when the till next reaches
     * /current or /bootstrap; an islanded till keeps trading until its
     * max_offline_days window closes.
     */
    public function revoke(Request $request, PosLicence $licence): JsonResponse
    {
        $validated = $request->validate([
            'reason' => ['nullable', 'string', 'max:255'],
        ]);

        $licence = $this->issuer->revoke($licence, $validated['reason'] ?? null, $request->user());

        return response()->json([
            'data' => PosLicenceResource::make($licence),
            'message' => __('xorder.messages.licence_revoked'),
        ]);
    }

    /**
     * Suspend, resume, force-expire (R2, POS-BE-031).
     *
     * Status changes on the online path only: a connected till hears it at its
     * next /license/check; an islanded till's signed file cannot be recalled,
     * so `enforcement` is in the response for the screen to say so. Refused on
     * a revoked or superseded licence — that row is history, and a status on
     * it would be a decision nobody can see take effect.
     */
    public function suspend(Request $request, PosLicence $licence): JsonResponse
    {
        $validated = $request->validate(['reason' => ['nullable', 'string', 'max:255']]);

        return $this->whenLive($licence, fn () => $this->statusResponse(
            $this->issuer->suspend($licence, $validated['reason'] ?? null, $request->user()),
            'licence_suspended',
        ));
    }

    public function resume(Request $request, PosLicence $licence): JsonResponse
    {
        return $this->whenLive($licence, fn () => $this->statusResponse(
            $this->issuer->resume($licence, $request->user()),
            'licence_resumed',
        ));
    }

    public function expire(Request $request, PosLicence $licence): JsonResponse
    {
        $validated = $request->validate(['reason' => ['nullable', 'string', 'max:255']]);

        return $this->whenLive($licence, fn () => $this->statusResponse(
            $this->issuer->expire($licence, $validated['reason'] ?? null, $request->user()),
            'licence_force_expired',
        ));
    }

    /**
     * The tills behind a licence, with when each last checked it (R2).
     *
     * Cross-tenant like the rest of this controller: names the licence's own
     * restaurant explicitly. An offline licence has no tenant and so no
     * terminals here — its tills never reach the platform.
     */
    public function terminals(PosLicence $licence): JsonResponse
    {
        $terminals = $licence->restaurant_id === null ? collect() : PosTerminal::query()
            ->withoutGlobalScopes()
            ->where('restaurant_id', $licence->restaurant_id)
            ->with('branch:id,name_en,name_ar,code')
            ->orderByDesc('id')
            ->get();

        return response()->json(['data' => PosTerminalResource::collection($terminals)]);
    }

    private function whenLive(PosLicence $licence, \Closure $action): JsonResponse
    {
        if ($licence->revoked_at !== null || $licence->superseded_by_id !== null) {
            return response()->json([
                'code' => 'LICENCE_NOT_LIVE',
                'message' => __('xorder.errors.licence_not_live'),
            ], 422);
        }

        return $action();
    }

    private function statusResponse(PosLicence $licence, string $message): JsonResponse
    {
        return response()->json([
            'data' => PosLicenceResource::make($licence),
            'message' => __('xorder.messages.'.$message),
        ]);
    }

    /**
     * Delete a licence record outright — owner decision, 2026-09-05.
     *
     * Deletion is CLEANUP, not enforcement: only a licence that no longer
     * permits trade (revoked, superseded, or fully expired past grace) may be
     * removed. Deleting an active licence would not stop a till holding its
     * file — the file verifies offline — it would only erase the record of
     * what was sold, so an active licence must be revoked first. The audit
     * trail keeps the tombstone.
     */
    public function destroy(Request $request, PosLicence $licence): JsonResponse
    {
        $state = $licence->state();
        if (! in_array($state, ['revoked', 'superseded', 'expired'], true)) {
            return response()->json([
                'code' => 'LICENCE_STILL_ACTIVE',
                'message' => __('xorder.errors.licence_still_active'),
            ], 422);
        }

        // Rows this one superseded keep their own history but lose the
        // dangling pointer; their state falls back to what their dates say.
        PosLicence::query()
            ->where('superseded_by_id', $licence->id)
            ->update(['superseded_by_id' => null]);

        AuditLogger::record('pos_licence.deleted', [
            'actor' => $request->user(),
            'restaurant_id' => $licence->restaurant_id,
            'description' => sprintf('POS licence %s deleted (state: %s)', $licence->licence_ref, $state),
            'properties' => [
                'licence_ref' => $licence->licence_ref,
                'key_last_four' => $licence->key_last_four,
                'state' => $state,
            ],
        ]);

        $licence->delete();

        return response()->json(['message' => __('xorder.messages.licence_deleted')]);
    }

    /**
     * Download the .xlic file.
     *
     * This is the on-premises delivery path: a till that may never reach the
     * internet in its working life still has to be licensable, and a signed file
     * carried in by hand is the only mechanism that survives that constraint.
     * Byte-identical to what the activation endpoint returns.
     */
    public function download(PosLicence $licence): StreamedResponse
    {
        $body = json_encode($licence->file(), JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
        $name = $licence->licence_ref.'.xlic';

        return response()->streamDownload(
            fn () => print $body,
            $name,
            ['Content-Type' => 'application/json'],
        );
    }
}
