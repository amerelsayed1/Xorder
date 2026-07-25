<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PushTokenController extends Controller
{
    /** Register (or refresh) this device's FCM token for the signed-in admin. */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:512'],
            'platform' => ['nullable', 'string', 'max:20'],
        ]);

        $user = $request->user();

        // The token column is globally unique. Refuse to re-point a token that
        // is already registered to a DIFFERENT account: without this, an admin
        // who obtained another tenant's FCM token could POST it here and hijack
        // that device's push routing. A device legitimately changing hands
        // clears its old token via the logout `destroy` call first.
        $existing = DeviceToken::where('token', $data['token'])->first();
        if ($existing !== null && $existing->user_id !== $user->id) {
            return response()->json(['message' => 'registered']); // no-op, no oracle
        }

        DeviceToken::updateOrCreate(
            ['token' => $data['token']],
            [
                'user_id' => $user->id,
                'restaurant_id' => $user->restaurant_id,
                'platform' => $data['platform'] ?? 'web',
            ],
        );

        return response()->json(['message' => 'registered']);
    }

    /** Drop a token (logout / notifications disabled). */
    public function destroy(Request $request): JsonResponse
    {
        $data = $request->validate(['token' => ['required', 'string', 'max:512']]);

        DeviceToken::where('token', $data['token'])
            ->where('user_id', $request->user()->id)
            ->delete();

        return response()->json(['message' => 'removed']);
    }
}
