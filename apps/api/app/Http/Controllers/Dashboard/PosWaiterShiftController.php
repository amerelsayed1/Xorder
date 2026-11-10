<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\PosWaiterShift;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * POS-BE-033 shift clock, the dashboard half: when each waiter started and
 * finished, for the manager. Read-only (the handheld is the only author).
 *
 * The range is restaurant-local calendar days, inclusive, and selects every
 * shift that OVERLAPS it — so a shift still open from yesterday shows on
 * today. Durations are whole minutes of the full shift (an open one counts
 * up to now), not clipped to the range. Every query names the caller's
 * restaurant on top of RestaurantScope.
 */
class PosWaiterShiftController extends Controller
{
    private const DEFAULT_DAYS = 7;

    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'from' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            'user_id' => ['sometimes', 'nullable', 'integer'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        $restaurant = $request->user()->restaurant;
        $restaurantId = $restaurant->id;
        $tz = $restaurant->localTimezone();

        $toDay = $request->filled('to') ? $request->input('to') : now($tz)->toDateString();
        $fromDay = $request->filled('from')
            ? $request->input('from')
            : Carbon::parse($toDay, $tz)->subDays(self::DEFAULT_DAYS - 1)->toDateString();

        if (Carbon::parse($fromDay)->diffInDays(Carbon::parse($toDay)) > 366) {
            $message = __('xorder.messages.waiter_shift_range_too_long');

            return response()->json(['message' => $message, 'errors' => ['to' => [$message]]], 422);
        }

        $from = Carbon::parse($fromDay, $tz)->startOfDay()->utc();
        $to = Carbon::parse($toDay, $tz)->endOfDay()->utc();
        $userId = $request->filled('user_id') ? $request->integer('user_id') : null;

        $query = fn () => PosWaiterShift::query()
            ->where('restaurant_id', $restaurantId)
            ->where('started_at', '<=', $to)
            ->where(fn ($q) => $q->whereNull('ended_at')->orWhere('ended_at', '>=', $from))
            ->when($userId !== null, fn ($q) => $q->where('user_id', $userId));

        $now = now();
        $minutes = fn (PosWaiterShift $s): int => intdiv(max(0, ($s->ended_at ?? $now)->getTimestamp() - $s->started_at->getTimestamp()), 60);

        $page = $query()
            ->with(['user:id,name', 'startedDevice:id,name', 'endedDevice:id,name'])
            ->orderByRaw('ended_at IS NOT NULL')
            ->orderByDesc('started_at')
            ->orderByDesc('id')
            ->paginate($request->integer('per_page', 25));

        $rows = collect($page->items())->map(fn (PosWaiterShift $s) => [
            'id' => $s->id,
            'user_id' => $s->user_id,
            'waiter_name' => $s->user?->name,
            'started_at' => $s->started_at->toIso8601ZuluString(),
            'ended_at' => $s->ended_at?->toIso8601ZuluString(),
            'open' => $s->isOpen(),
            'duration_minutes' => $minutes($s),
            'started_device' => $s->startedDevice?->name,
            'ended_device' => $s->endedDevice?->name,
        ]);

        // Per-waiter totals over the whole range (not just this page).
        $totals = [];
        foreach ($query()->select(['id', 'user_id', 'started_at', 'ended_at'])->cursor() as $s) {
            $t = $totals[$s->user_id] ??= ['user_id' => $s->user_id, 'shifts' => 0, 'minutes' => 0, 'on_shift' => false];
            $t['shifts']++;
            $t['minutes'] += $minutes($s);
            $t['on_shift'] = $t['on_shift'] || $s->isOpen();
            $totals[$s->user_id] = $t;
        }

        // Everyone who has ever clocked in here: the waiter filter's options.
        $waiterIds = PosWaiterShift::query()->where('restaurant_id', $restaurantId)->distinct()->pluck('user_id');
        $waiters = User::query()
            ->where('restaurant_id', $restaurantId)
            ->whereIn('id', $waiterIds)
            ->orderBy('name')
            ->get(['id', 'name']);
        $names = $waiters->pluck('name', 'id');

        $totals = collect($totals)
            ->map(fn (array $t) => $t + ['waiter_name' => $names[$t['user_id']] ?? null])
            ->sortByDesc('minutes')
            ->values();

        return response()->json([
            'data' => $rows,
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
            'range' => ['from' => $fromDay, 'to' => $toDay, 'timezone' => $tz],
            'totals' => $totals,
            'waiters' => $waiters->map(fn (User $u) => ['id' => $u->id, 'name' => $u->name])->values(),
        ]);
    }
}
