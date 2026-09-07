<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StorePosTerminalRequest;
use App\Http\Resources\PosTerminalResource;
use App\Models\PosTerminal;
use App\Services\PosProvisioningService;
use App\Support\PairingCode;
use Illuminate\Http\JsonResponse;

/**
 * POS-BE-023, the dashboard half: provision → pairing code → (the till
 * claims) → revoke. Route stack: role + feature:pos + can:pos.provision +
 * subscription.writable on writes. RestaurantScope scopes every query.
 */
class PosTerminalController extends Controller
{
    public function __construct(private readonly PosProvisioningService $service) {}

    public function index(): JsonResponse
    {
        $terminals = PosTerminal::with('branch:id,name_en,name_ar,code')
            ->orderByDesc('id')
            ->get();

        return response()->json(['data' => PosTerminalResource::collection($terminals)]);
    }

    public function store(StorePosTerminalRequest $request): JsonResponse
    {
        $terminal = $this->service->provision(
            $request->user()->restaurant,
            $request->user(),
            $request->validated(),
        );

        return response()->json([
            'data' => PosTerminalResource::make($terminal),
            'message' => __('xorder.messages.pos_terminal_provisioned'),
        ], 201);
    }

    /**
     * Issue / regenerate the pairing code. The plaintext appears in THIS
     * response and never again — the server keeps only the HMAC, exactly like
     * a licence activation key.
     */
    public function pairingCode(PosTerminal $terminal): JsonResponse
    {
        if ($terminal->isRevoked()) {
            return response()->json(['message' => __('xorder.messages.pos_terminal_revoked')], 422);
        }

        return response()->json([
            'pairing_code' => $this->service->issuePairingCode($terminal, request()->user()),
            'expires_in_hours' => PairingCode::TTL_HOURS,
        ]);
    }

    /** BE-A04: revocation stops FUTURE trade; history is untouched. */
    public function revoke(PosTerminal $terminal): JsonResponse
    {
        $this->service->revoke($terminal, request()->user());

        return response()->json(['message' => __('xorder.messages.pos_terminal_revoked')]);
    }

    /**
     * Delete a terminal record outright — owner decision, 2026-09-05, the same
     * split as licences: revoke stops trade, delete is cleanup.
     *
     * The rules (revoked first, no money history) live in the service, so this
     * front door and the Super Admin's cannot drift apart.
     */
    public function destroy(PosTerminal $terminal): JsonResponse
    {
        $this->service->delete($terminal, request()->user());

        return response()->json(['message' => __('xorder.messages.pos_terminal_deleted')]);
    }
}
