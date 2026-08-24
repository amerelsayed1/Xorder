<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Models\BillRequest;
use App\Models\Notification;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * One consolidated heartbeat for the dashboard shell. Replaces the three
 * separate badge polls (new orders, new bill requests, unread notifications)
 * with a single request, and short-circuits to a bodyless 304 via ETag when
 * nothing changed — so idle tabs cost almost nothing on the wire.
 *
 * Counts respect the same feature gates as their dedicated endpoints: a plan
 * without system_ordering / bill_requests simply reports null for that count,
 * matching what the gated endpoints would (not) return — and so does a user
 * whose role lacks the matching capability, so a cook never sees a badge for a
 * queue they cannot open.
 */
class PulseController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        $user = $request->user();

        $newOrders = $restaurant?->hasFeature('system_ordering') && $user->can('orders.view')
            ? Order::where('status', OrderStatus::NEW)->count()
            : null;

        $newRequests = $restaurant?->hasFeature('bill_requests') && $user->can('bills.view')
            ? BillRequest::where('status', BillRequestStatus::REQUESTED->value)->count()
            : null;

        $unread = Notification::whereNull('read_at')->count();
        // The newest id lets the client tell "a notification arrived" apart from
        // "one was marked read elsewhere" when the unread count moves.
        $latestId = Notification::max('id') ?? 0;

        $payload = [
            'new_orders' => $newOrders,
            'new_requests' => $newRequests,
            'unread_notifications' => $unread,
            'latest_notification_id' => (int) $latestId,
        ];

        // ETag over the moving parts. isNotModified() compares the client's
        // If-None-Match and, on a match, strips the body and flips the status to
        // 304 — so an idle tab's poll costs a bare header round-trip.
        $response = response()->json(['data' => $payload]);
        $response->setEtag(md5(implode(':', [$newOrders ?? '-', $newRequests ?? '-', $unread, $latestId])));
        $response->isNotModified($request);

        return $response;
    }
}
