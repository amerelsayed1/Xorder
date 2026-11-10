<?php

namespace App\Services;

use App\Models\PosWaiterDevice;
use App\Models\PosWaiterShift;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;

/**
 * The waiter shift clock (POS-BE-033): one open shift per waiter, whichever
 * device. Mirrors the Dart reference backend (xorder_waiter_link server.dart
 * `openShift` / `startShift` / `finishShift`).
 */
class WaiterShiftService
{
    public function open(Restaurant $restaurant, User $user): ?PosWaiterShift
    {
        return PosWaiterShift::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('user_id', $user->id)
            ->whereNull('ended_at')
            ->first();
    }

    /** Open a shift now on [device]; an already-open one comes back as it is. */
    public function start(Restaurant $restaurant, User $user, PosWaiterDevice $device): PosWaiterShift
    {
        $open = $this->open($restaurant, $user);

        if ($open !== null) {
            return $open;
        }

        try {
            $shift = new PosWaiterShift;
            $shift->forceFill([
                'restaurant_id' => $restaurant->id,
                'user_id' => $user->id,
                'started_device_id' => $device->id,
                'started_at' => now(),
            ])->save();

            return $shift;
        } catch (UniqueConstraintViolationException) {
            // Two devices pressed Start at once: the partial unique index let
            // one through; that one is the waiter's shift.
            return $this->open($restaurant, $user) ?? throw new \LogicException('open shift vanished');
        }
    }

    /** Close the open shift now on [device]; null when none is open. */
    public function finish(Restaurant $restaurant, User $user, PosWaiterDevice $device): ?PosWaiterShift
    {
        $open = $this->open($restaurant, $user);

        if ($open === null) {
            return null;
        }

        $now = now();

        // Conditional on still being open, so a finish racing another finish
        // closes it once and the loser answers NO_OPEN_SHIFT.
        $closed = PosWaiterShift::query()
            ->where('restaurant_id', $restaurant->id)
            ->whereKey($open->id)
            ->whereNull('ended_at')
            ->update(['ended_at' => $now, 'ended_device_id' => $device->id, 'updated_at' => $now]);

        return $closed === 1 ? $open->fresh() : null;
    }
}
