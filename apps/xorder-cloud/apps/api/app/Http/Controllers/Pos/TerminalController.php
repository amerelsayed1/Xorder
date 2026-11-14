<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\ClaimTerminalRequest;
use App\Http\Requests\Pos\HeartbeatRequest;
use App\Http\Requests\Pos\RegisterTerminalRequest;
use App\Models\PosTerminal;
use App\Services\PosProvisioningService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The till's own lifecycle (POS-BE-011/022/023): claim, register, token
 * rotation, heartbeat. Thin — every rule lives in PosProvisioningService.
 */
class TerminalController extends Controller
{
    public function __construct(private readonly PosProvisioningService $service) {}

    /** Path A. Unauthenticated; the pairing code is the credential; throttled. */
    public function claim(ClaimTerminalRequest $request): JsonResponse
    {
        ['body' => $body] = $this->service->claim($request->validated());

        return response()->json($body);
    }

    /** Path B. Staff JWT holding pos.provision; used once, never stored by the till. */
    public function register(RegisterTerminalRequest $request): JsonResponse
    {
        ['body' => $body, 'replay' => $replay] = $this->service->register(
            $request->user(),
            $request->validated(),
        );

        return response()->json($body, $replay ? 200 : 201);
    }

    /** Device credential rotation — old token keeps working 24h (POS-BE-011). */
    public function rotateToken(Request $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        return response()->json([
            'device_token' => $this->service->rotateToken($terminal),
            'server_time' => now()->toIso8601String(),
        ]);
    }

    /**
     * POS-BE-022. Small, frequent, automatic; carries no money; last write
     * wins. Deliberately NOT feature-gated (the middleware runs in no-feature
     * mode) — a lapsed feature must not silence the fleet view.
     */
    public function heartbeat(HeartbeatRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        return response()->json($this->service->heartbeat($terminal, $request->validated()));
    }
}
