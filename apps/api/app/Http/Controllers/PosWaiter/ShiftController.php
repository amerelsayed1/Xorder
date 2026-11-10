<?php

namespace App\Http\Controllers\PosWaiter;

use App\Exceptions\WaiterWireException;
use App\Http\Controllers\Controller;
use App\Models\PosWaiterDevice;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\WaiterShiftService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-033 — the waiter's shift clock (wire v1). A waiter starts a shift
 * before the floor opens and finishes it when leaving; signing out does not
 * finish it. Not itself gated on an open shift.
 */
class ShiftController extends Controller
{
    public function __construct(private readonly WaiterShiftService $shifts) {}

    public function show(Request $request): JsonResponse
    {
        return response()->json(['shift' => $this->shifts->open($this->restaurant($request), $this->user($request))?->toWire()]);
    }

    public function start(Request $request): JsonResponse
    {
        $shift = $this->shifts->start($this->restaurant($request), $this->user($request), $this->device($request));

        return response()->json(['shift' => $shift->toWire()]);
    }

    public function finish(Request $request): JsonResponse
    {
        $shift = $this->shifts->finish($this->restaurant($request), $this->user($request), $this->device($request));

        if ($shift === null) {
            throw new WaiterWireException('NO_OPEN_SHIFT', 409);
        }

        return response()->json(['shift' => $shift->toWire()]);
    }

    private function restaurant(Request $request): Restaurant
    {
        return $request->attributes->get('waiter_restaurant');
    }

    private function user(Request $request): User
    {
        return $request->attributes->get('waiter_user');
    }

    private function device(Request $request): PosWaiterDevice
    {
        return $request->attributes->get('waiter_device');
    }
}
