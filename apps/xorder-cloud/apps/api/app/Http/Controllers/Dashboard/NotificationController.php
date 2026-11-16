<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Resources\NotificationResource;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The restaurant's durable notification feed. Every query is tenant-scoped by
 * the RestaurantScope global scope, so an admin only ever sees — and can only
 * mark read — their own restaurant's notifications, including the implicit
 * route-model binding on {notification}.
 */
class NotificationController extends Controller
{
    /** Latest notifications, newest first. `?unread=1` limits to unread. */
    public function index(Request $request): JsonResponse
    {
        $notifications = Notification::query()
            ->visibleTo($request->user())
            ->when($request->boolean('unread'), fn ($q) => $q->whereNull('read_at'))
            ->latest('id')
            ->paginate(20);

        return NotificationResource::collection($notifications)->response();
    }

    /** Lightweight unread badge count. */
    public function unreadCount(Request $request): JsonResponse
    {
        return response()->json([
            'data' => ['unread' => Notification::visibleTo($request->user())->whereNull('read_at')->count()],
        ]);
    }

    /**
     * Mark a single notification read (idempotent). One this account may not see
     * answers 404, exactly like another restaurant's, so its existence is not
     * confirmed.
     */
    public function markRead(Request $request, Notification $notification): JsonResponse
    {
        abort_unless(Notification::typeVisibleTo($notification->type, $request->user()), 404);

        if ($notification->read_at === null) {
            $notification->forceFill(['read_at' => now()])->save();
        }

        return response()->json(['data' => NotificationResource::make($notification)]);
    }

    /** Mark every unread notification this account may see as read; returns how many were cleared. */
    public function markAllRead(Request $request): JsonResponse
    {
        $cleared = Notification::visibleTo($request->user())->whereNull('read_at')->update(['read_at' => now()]);

        return response()->json(['data' => ['cleared' => $cleared]]);
    }
}
