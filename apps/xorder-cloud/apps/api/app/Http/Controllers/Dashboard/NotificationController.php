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
            ->when($request->boolean('unread'), fn ($q) => $q->whereNull('read_at'))
            ->latest('id')
            ->paginate(20);

        return NotificationResource::collection($notifications)->response();
    }

    /** Lightweight unread badge count. */
    public function unreadCount(): JsonResponse
    {
        return response()->json([
            'data' => ['unread' => Notification::whereNull('read_at')->count()],
        ]);
    }

    /** Mark a single notification read (idempotent). */
    public function markRead(Notification $notification): JsonResponse
    {
        if ($notification->read_at === null) {
            $notification->forceFill(['read_at' => now()])->save();
        }

        return response()->json(['data' => NotificationResource::make($notification)]);
    }

    /** Mark every unread notification read; returns how many were cleared. */
    public function markAllRead(): JsonResponse
    {
        $cleared = Notification::whereNull('read_at')->update(['read_at' => now()]);

        return response()->json(['data' => ['cleared' => $cleared]]);
    }
}
