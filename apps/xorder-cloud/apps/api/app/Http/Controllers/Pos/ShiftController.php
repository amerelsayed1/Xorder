<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\CloseShiftRequest;
use App\Http\Requests\Pos\OpenShiftRequest;
use App\Http\Requests\Pos\StoreCashMovementRequest;
use App\Http\Resources\PosShiftResource;
use App\Models\PosTerminal;
use App\Services\PosShiftService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** POS-BE-009. {id} accepts the server id or the shift's client uuid. */
class ShiftController extends Controller
{
    public function __construct(private readonly PosShiftService $service) {}

    public function open(OpenShiftRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['shift' => $shift, 'replay' => $replay] = $this->service->open($terminal, $request->validated());

        return response()->json(['data' => PosShiftResource::make($shift)], $replay ? 200 : 201);
    }

    public function current(Request $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        $shift = $this->service->current($terminal);

        return response()->json(['data' => $shift ? PosShiftResource::make($shift) : null]);
    }

    public function close(CloseShiftRequest $request, string $shift): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['shift' => $closed] = $this->service->close($terminal, $shift, $request->validated());

        return response()->json(['data' => PosShiftResource::make($closed)]);
    }

    public function report(Request $request, string $shift): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        $report = $this->service->report($terminal, $shift);
        $report['shift'] = PosShiftResource::make($report['shift']);

        return response()->json(['data' => $report]);
    }

    public function cashMovement(StoreCashMovementRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['movement' => $movement, 'replay' => $replay] = $this->service->cashMovement($terminal, $request->validated());

        return response()->json([
            'data' => [
                'id' => $movement->id,
                'client_transaction_id' => $movement->client_transaction_id,
                'direction' => $movement->direction,
                'amount_minor' => (int) $movement->amount_minor,
                'reason' => $movement->reason,
                'occurred_at' => $movement->occurred_at?->toIso8601String(),
            ],
        ], $replay ? 200 : 201);
    }
}
