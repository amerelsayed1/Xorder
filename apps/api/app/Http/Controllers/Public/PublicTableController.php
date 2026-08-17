<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Services\BranchEgressIpService;
use App\Support\GeoFence;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Public entry point for a table QR scan. Resolves the opaque token to its
 * restaurant/branch/area/table (never exposing the internal id) and opens a
 * table-bound menu session.
 */
class PublicTableController extends Controller
{
    /**
     * Cap on how far the device's reported GPS accuracy may widen the fence.
     * Absorbs normal mobile jitter (typically 20–65 m) without letting a wildly
     * uncertain fix (e.g. IP-only, hundreds of metres) defeat the fence.
     */
    private const MAX_ACCURACY_TOLERANCE_M = 75.0;

    /** GET /public/tables/{token} — table context for the menu banner. */
    public function show(string $token): JsonResponse
    {
        return response()->json(['data' => $this->context($this->resolve($token))]);
    }

    /** POST /public/tables/{token}/sessions — start a table menu session. */
    public function createSession(Request $request, string $token, BranchEgressIpService $egressIps): JsonResponse
    {
        $validated = $request->validate([
            'language' => ['nullable', 'in:ar,en'],
            // Diner's device GPS, sent when the branch fence is enabled.
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            // Device-reported fix accuracy (metres); widens the fence to match.
            'accuracy' => ['nullable', 'numeric', 'min:0'],
        ]);

        $table = $this->resolve($token);

        // Presence check: if the branch fences its premises, the scanner must be
        // physically inside it. GPS is the only trustworthy signal, so a missing
        // location fails closed (no spoofable manual fallback).
        $this->enforceGeofence(
            $table,
            $validated['latitude'] ?? null,
            $validated['longitude'] ?? null,
            $validated['accuracy'] ?? null,
        );

        $ttl = (int) config('platform.table_session_ttl_minutes', 240);
        $clientIp = $request->ip();

        // Wi-Fi gate, when the branch has opted in. Runs after the fence so a
        // diner who fails both is told about location first — the one they can
        // actually act on without changing networks.
        $this->enforceBranchWifi($table, $egressIps, $clientIp);

        $session = new MenuSession([
            'branch_id' => $table->branch_id,
            'dining_area_id' => $table->dining_area_id,
            'table_id' => $table->id,
            'language' => $request->input('language') ?? $table->restaurant->default_language->value,
            'session_token' => Str::random(40),
            // Evidence that admitted this session, kept rather than discarded:
            // it is the only record available if presence is later disputed, and
            // it is what BranchEgressIpService learns the branch's customer
            // Wi-Fi address from. Recorded, not enforced — see below.
            'client_ip' => $clientIp,
            'latitude' => $validated['latitude'] ?? null,
            'longitude' => $validated['longitude'] ?? null,
            'accuracy_m' => isset($validated['accuracy'])
                ? (int) round(min((float) $validated['accuracy'], 65535))
                : null,
            'presence_source' => $this->fenceRequired($table) ? MenuSession::PRESENCE_GEOFENCE : null,
            // Whether the diner reached us from the branch's own line. Observed
            // only: a match is corroboration, and a miss means nothing (most
            // diners are on mobile data), so it deliberately does not gate the
            // session. Promote it to enforcement only once the recorded data
            // shows how often it actually fires.
            'on_branch_network' => $egressIps->matches($table->branch, $clientIp),
            'started_at' => now(),
            'last_activity_at' => now(),
            'expires_at' => now()->addMinutes($ttl),
        ]);
        $session->restaurant_id = $table->restaurant_id;
        $session->save();

        return response()->json([
            'data' => $this->context($table) + [
                'session_token' => $session->session_token,
                'expires_at' => $session->expires_at,
            ],
        ], 201);
    }

    /**
     * Look up the table and enforce the scan-time guards (FR-SESSION-006/007/008).
     */
    private function resolve(string $token): DiningTable
    {
        $table = DiningTable::withoutGlobalScopes()
            ->with(['restaurant.features', 'branch', 'diningArea'])
            ->where('public_token', $token)
            ->first();

        if ($table === null) {
            abort(404, __('xorder.messages.table_qr_invalid'));
        }
        if (! $table->restaurant->isPubliclyVisible()) {
            abort(403, __('xorder.messages.menu_unavailable'));
        }
        if (! $table->is_active) {
            abort(403, __('xorder.messages.table_disabled'));
        }
        if ($table->branch && ! $table->branch->is_active) {
            abort(403, __('xorder.messages.branch_disabled'));
        }

        return $table;
    }

    /**
     * A fence-derived "good enough" GPS accuracy (metres) the menu aims for
     * before it stops sampling location: about half the fence's characteristic
     * size, so a tight fence demands a tighter fix and a large one settles for a
     * looser one. Floored so we never ask for a precision phones can't reach,
     * ceiled so a big fence still stops quickly, and rounded to 5 m so it only
     * coarsely reflects the fence's scale. Null when no fence applies.
     */
    private function locationTargetAccuracy(DiningTable $table): ?int
    {
        if (! $this->fenceRequired($table)) {
            return null;
        }

        $size = GeoFence::characteristicRadiusMetres($table->branch->geofence);
        if ($size === null) {
            return null;
        }

        $target = min(60.0, max(15.0, $size * 0.5));

        return (int) (round($target / 5) * 5);
    }

    /** Does this table's branch enforce an on-premises presence fence? */
    private function fenceRequired(DiningTable $table): bool
    {
        // TEMPORARY master switch (config/platform.php). While off, no scan is
        // asked for GPS or refused for being out of area, whatever a branch has
        // saved — the single gate every other path here reads.
        if (! config('platform.presence.geofence_enforcement', false)) {
            return false;
        }

        $branch = $table->branch;

        return $branch !== null
            && $branch->geofence_enabled
            && GeoFence::isEnforceable($branch->geofence);
    }

    /**
     * Refuse the session unless the scan arrives from the branch's own customer
     * Wi-Fi, for a branch that has switched that requirement on.
     *
     * Fails closed on every answer that is not a definite match — including
     * "we have no addresses on file", which `matches()` reports as null. That
     * is the strict reading the requirement asks for, and the branch form will
     * not let the switch be turned on without at least one address, so the
     * unanswerable state cannot be reached by simply enabling it.
     *
     * Worth restating what this costs, because the enforcement contradicts the
     * signal's own limits (see BranchEgressIpService): a diner on mobile data,
     * on iOS Private Relay, or behind any VPN is refused while sitting at the
     * table, and a dynamic line that rotates its address refuses everyone until
     * the new one is declared. Off by default for exactly that reason.
     */
    private function enforceBranchWifi(DiningTable $table, BranchEgressIpService $egressIps, ?string $clientIp): void
    {
        $branch = $table->branch;

        if ($branch === null || ! $branch->require_branch_wifi) {
            return;
        }

        if ($egressIps->matches($branch, $clientIp) !== true) {
            abort(422, __('xorder.messages.table_requires_branch_wifi'));
        }
    }

    /**
     * Refuse the session unless the scanner's GPS falls inside the branch fence.
     * Fails closed: fence on but no coordinates → 422 (location required);
     * coordinates outside the polygon → 422 (out of area). No fence → no-op.
     */
    private function enforceGeofence(DiningTable $table, ?float $lat, ?float $lng, ?float $accuracy = null): void
    {
        if (! $this->fenceRequired($table)) {
            return;
        }

        if ($lat === null || $lng === null) {
            abort(422, __('xorder.messages.table_location_required'));
        }

        // A GPS fix is only ever precise to within its accuracy radius, so widen
        // the fence by that much (capped) before testing — otherwise a diner who
        // is genuinely inside but whose phone reports a fuzzy fix is locked out.
        $tolerance = $accuracy === null ? 0.0 : min(max(0.0, $accuracy), self::MAX_ACCURACY_TOLERANCE_M);

        if (! GeoFence::contains($lat, $lng, $table->branch->geofence, $tolerance)) {
            abort(422, __('xorder.messages.table_outside_area'));
        }
    }

    /** @return array<string,mixed> */
    private function context(DiningTable $table): array
    {
        $r = $table->restaurant;

        return [
            'restaurant' => [
                'slug' => $r->slug,
                'name_ar' => $r->name_ar,
                'name_en' => $r->name_en,
                'default_language' => $r->default_language->value,
                'bilingual' => $r->bilingual,
            ],
            'branch' => $table->branch ? ['name_ar' => $table->branch->name_ar, 'name_en' => $table->branch->name_en] : null,
            'area' => $table->diningArea ? ['name_ar' => $table->diningArea->name_ar, 'name_en' => $table->diningArea->name_en] : null,
            'table' => ['label' => $table->label],
            'order_type' => 'dine_in',
            // Signals the menu to obtain the diner's GPS before it tries to open
            // a session — createSession refuses without an in-fence location.
            'geofence_required' => $this->fenceRequired($table),
            // How precise a fix the menu should hold out for, scaled to this
            // fence's size (null when no fence). Lets the client stop sampling
            // as soon as it's accurate enough for this specific premises.
            'location_target_accuracy_m' => $this->locationTargetAccuracy($table),
            'bill_requests' => (bool) $table->restaurant->hasFeature('bill_requests'),
            'internal_reviews' => (bool) $table->restaurant->hasFeature('internal_reviews'),
        ];
    }
}
