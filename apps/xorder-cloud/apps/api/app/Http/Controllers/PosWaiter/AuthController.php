<?php

namespace App\Http\Controllers\PosWaiter;

use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Exceptions\WaiterWireException;
use App\Http\Controllers\Controller;
use App\Http\Middleware\WaiterWire;
use App\Models\PosWaiterDevice;
use App\Models\PosWaiterSession;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\WaiterShiftService;
use App\Support\PosPin;
use App\Support\WaiterToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * POS-BE-033 — hello, sign-in and sign-out of the waiter wire (wire v1).
 *
 * Sign-in is the one call a phone the platform does not know yet may make: it
 * registers the phone as a device and returns the device token ONCE. The PIN is
 * the POS PIN of POS-BE-024 (never the dashboard password), matched together
 * with the staff username; one error for either wrong.
 */
class AuthController extends Controller
{
    public const WIRE = 1;

    private const MAX_FAILURES = 5;

    private const LOCKOUT_SECONDS = 60;

    public function hello(Request $request): JsonResponse
    {
        /** @var Restaurant $restaurant */
        $restaurant = $request->attributes->get('waiter_restaurant');

        return response()->json([
            'wire' => self::WIRE,
            'name' => $restaurant->name_en ?: ($restaurant->name_ar ?: $restaurant->slug),
        ]);
    }

    public function signIn(Request $request): JsonResponse
    {
        /** @var Restaurant $restaurant */
        $restaurant = $request->attributes->get('waiter_restaurant');

        $username = $request->input('username');
        $pin = $request->input('pin');
        $deviceName = $request->input('device_name');

        if (! is_string($username) || trim($username) === '' || ! is_string($pin) || $pin === '') {
            throw new WaiterWireException('BAD_REQUEST', 400);
        }

        // A known device is checked first (unknown → UNPAIRED, revoked → DEVICE_REVOKED).
        $device = WaiterWire::deviceFromHeader($request, $restaurant);

        // Failures are counted per device, or per IP for a phone with no token yet.
        $limiterKey = sprintf('waiter-signin:%d:%s', $restaurant->id, $device !== null ? 'd'.$device->id : 'ip'.$request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, self::MAX_FAILURES)) {
            throw new WaiterWireException('TOO_MANY_ATTEMPTS', 429, [
                'retry_after' => RateLimiter::availableIn($limiterKey),
            ]);
        }

        $user = User::query()
            ->with('tenantRole')
            ->where('restaurant_id', $restaurant->id)
            ->where('username', trim($username))
            ->where('status', UserStatus::ACTIVE)
            ->first();

        $valid = $user !== null
            && $user->isTenantUser()
            && PosPin::verify($pin, $user->pos_pin_salt, $user->pos_pin_hash);

        if ($user === null) {
            // Spend the same time as a real check so an unknown username is not
            // distinguishable from a wrong PIN by latency.
            PosPin::verify($pin, base64_encode(str_repeat("\0", 16)), base64_encode(str_repeat("\0", 32)));
        }

        if (! $valid) {
            RateLimiter::hit($limiterKey, self::LOCKOUT_SECONDS);

            throw new WaiterWireException('PIN_WRONG', 401);
        }

        RateLimiter::clear($limiterKey);

        if (! $user->holdsTenantCapability(TenantCapability::POS_OPERATE)) {
            throw new WaiterWireException('NOT_PERMITTED', 403, ['reason' => 'pos_operate']);
        }

        $deviceToken = null;

        if ($device === null) {
            $deviceToken = WaiterToken::device();
            $device = new PosWaiterDevice;
            $device->forceFill([
                'restaurant_id' => $restaurant->id,
                'name' => mb_substr(is_string($deviceName) && trim($deviceName) !== '' ? trim($deviceName) : $user->name, 0, 120),
                'token_hash' => WaiterToken::hash($deviceToken),
                'created_by' => $user->id,
                'last_seen_at' => now(),
            ])->save();
        }

        $sessionToken = WaiterToken::session();
        (new PosWaiterSession)->forceFill([
            'restaurant_id' => $restaurant->id,
            'device_id' => $device->id,
            'user_id' => $user->id,
            'token_hash' => WaiterToken::hash($sessionToken),
            'last_seen_at' => now(),
        ])->save();

        // The waiter's open shift, whichever device started it; omitted when
        // none (they start one before the floor opens).
        $shift = app(WaiterShiftService::class)->open($restaurant, $user);

        return response()->json([
            'session' => $sessionToken,
            'staff' => [
                'id' => $user->id,
                'name' => $user->name,
                'capabilities' => $user->tenantCapabilities(),
            ],
        ] + ($deviceToken !== null ? ['device_token' => $deviceToken] : [])
          + ($shift !== null ? ['shift' => $shift->toWire()] : []));
    }

    /** Signing out ends the session only; an open shift stays open. */
    public function signOut(Request $request): JsonResponse
    {
        /** @var Restaurant $restaurant */
        $restaurant = $request->attributes->get('waiter_restaurant');
        /** @var PosWaiterDevice $device */
        $device = $request->attributes->get('waiter_device');

        $token = (string) $request->header('X-Waiter-Session', '');

        if (WaiterToken::looksValid($token, WaiterToken::SESSION_PREFIX)) {
            PosWaiterSession::query()
                ->where('restaurant_id', $restaurant->id)
                ->where('device_id', $device->id)
                ->where('token_hash', WaiterToken::hash($token))
                ->delete();
        }

        return response()->json(['ok' => true]);
    }
}
