<?php

namespace App\Services;

use App\Models\Notification;

/**
 * Single entry point for dashboard notifications. Records a durable row (so the
 * notification centre survives reloads and a fresh device sees history) and
 * then fans the same alert out over FCM web-push — best-effort, so a Firebase
 * hiccup never blocks the domain flow that raised the notification.
 *
 * Callers commonly wrap this in app()->terminating(...) so the push round-trip
 * happens after the response is flushed and never delays the request.
 */
class NotificationService
{
    public function __construct(private readonly PushService $push) {}

    /**
     * Record + push a notification for a restaurant.
     *
     * @param  string  $type  dotted event key, e.g. 'order.created'
     * @param  array<string,mixed>  $data  payload merged into the record and push
     * @param  string  $link  where a click lands (also stored as data.url)
     */
    public function toRestaurant(
        int $restaurantId,
        string $type,
        string $title,
        string $body,
        array $data = [],
        string $link = '/admin',
    ): Notification {
        $notification = new Notification([
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data + ['url' => $link],
        ]);
        // Set explicitly so it lands on the right tenant even from a public
        // request with no resolved TenantContext (the BelongsToRestaurant
        // creating hook only fills a null restaurant_id).
        $notification->restaurant_id = $restaurantId;
        $notification->save();

        $this->push->toRestaurant($restaurantId, $title, $body, $data, $link);

        return $notification;
    }
}
