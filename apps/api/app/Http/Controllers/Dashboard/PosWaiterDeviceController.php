<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\PosWaiterDevice;
use App\Models\PosWaiterSession;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-033, the dashboard half: the waiter phones a restaurant has, and
 * revoking one. Listing rides tables.view and revoking tables.update (a phone
 * is table-service equipment); every query names the caller's restaurant.
 */
class PosWaiterDeviceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $devices = PosWaiterDevice::query()
            ->where('restaurant_id', $request->user()->restaurant_id)
            ->orderByDesc('id')
            ->get(['id', 'name', 'last_seen_at', 'revoked_at', 'created_at']);

        return response()->json(['data' => $devices]);
    }

    public function revoke(Request $request, int $device): JsonResponse
    {
        $row = PosWaiterDevice::query()
            ->where('restaurant_id', $request->user()->restaurant_id)
            ->find($device);

        if ($row === null) {
            return response()->json(['message' => __('xorder.messages.waiter_device_not_found')], 404);
        }

        if (! $row->isRevoked()) {
            $row->forceFill(['revoked_at' => now()])->save();
        }

        // Its signed-in waiters are signed out with it.
        PosWaiterSession::query()->where('device_id', $row->id)->delete();

        return response()->json(['data' => $row->only(['id', 'name', 'last_seen_at', 'revoked_at', 'created_at'])]);
    }
}
