<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StorePosTerminalRequest;
use App\Http\Resources\PosTerminalResource;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Services\PosProvisioningService;
use App\Support\PairingCode;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Terminals of ONE tenant, from the platform side (owner decision,
 * 2026-09-05).
 *
 * This is the second half of the split that tenant creation made: creating a
 * tenant mints the tenant and its licence and NOTHING else, so the terminals
 * a client runs are created here — one at a time, each one an explicit act by
 * a Super Admin standing on that tenant's page. A tenant with zero terminals
 * is not an incomplete tenant; it is a tenant nobody has installed a till for
 * yet.
 *
 * Cross-tenant like every other /api/admin/* POS surface: the actor has no
 * tenant of their own, so the restaurant comes from the ROUTE and every query
 * below names it. Reads are can:pos_fleet.view (POS-BE-022); writes are
 * can:pos_fleet.manage, both SUPER_ADMIN-only by default.
 *
 * Deliberately NOT a second implementation: creation and pairing both go
 * through PosProvisioningService, the same service the restaurant's own
 * dashboard uses, so a terminal created from here is byte-for-byte the same
 * row as one the restaurant provisioned itself.
 */
class RestaurantTerminalController extends Controller
{
    public function __construct(private readonly PosProvisioningService $service) {}

    public function index(Restaurant $restaurant): JsonResponse
    {
        $terminals = PosTerminal::query()
            ->where('restaurant_id', $restaurant->id)
            ->with('branch:id,name_en,name_ar,code')
            ->orderByDesc('id')
            ->get();

        return response()->json(['data' => PosTerminalResource::collection($terminals)]);
    }

    public function store(StorePosTerminalRequest $request, Restaurant $restaurant): JsonResponse
    {
        $terminal = $this->service->provision($restaurant, $request->user(), $request->validated());

        return response()->json([
            'data' => PosTerminalResource::make($terminal->load('branch:id,name_en,name_ar,code')),
            'message' => __('xorder.messages.pos_terminal_provisioned'),
        ], 201);
    }

    /**
     * Issue / regenerate the pairing code the till types in to claim this
     * terminal. The plaintext appears in THIS response and never again — the
     * server keeps only the HMAC, exactly like a licence activation key.
     */
    public function pairingCode(Request $request, Restaurant $restaurant, PosTerminal $terminal): JsonResponse
    {
        $this->assertBelongsTo($restaurant, $terminal);

        if ($terminal->isRevoked()) {
            return response()->json(['message' => __('xorder.messages.pos_terminal_revoked')], 422);
        }

        return response()->json([
            'pairing_code' => $this->service->issuePairingCode($terminal, $request->user()),
            'expires_in_hours' => PairingCode::TTL_HOURS,
        ]);
    }

    /** BE-A04: revocation stops FUTURE trade; history is untouched. */
    public function revoke(Request $request, Restaurant $restaurant, PosTerminal $terminal): JsonResponse
    {
        $this->assertBelongsTo($restaurant, $terminal);

        $this->service->revoke($terminal, $request->user());

        return response()->json(['message' => __('xorder.messages.pos_terminal_revoked')]);
    }

    /**
     * Delete the record. Revoke stops trade; this is cleanup, and the service
     * refuses anything still active or holding sales/shift history.
     */
    public function destroy(Request $request, Restaurant $restaurant, PosTerminal $terminal): JsonResponse
    {
        $this->assertBelongsTo($restaurant, $terminal);

        $this->service->delete($terminal, $request->user());

        return response()->json(['message' => __('xorder.messages.pos_terminal_deleted')]);
    }

    /**
     * RestaurantScope is a no-op for an actor with no tenant, so binding a
     * terminal by id would otherwise happily resolve one belonging to a
     * different client. 404, not 403 — same no-existence-leak posture as a
     * foreign branch id.
     */
    private function assertBelongsTo(Restaurant $restaurant, PosTerminal $terminal): void
    {
        abort_unless($terminal->restaurant_id === $restaurant->id, 404);
    }
}
