<?php

namespace App\Services;

use App\Models\DeviceToken;
use Illuminate\Support\Facades\Log;
use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification as FcmNotification;
use Kreait\Firebase\Messaging\WebPushConfig;

/**
 * Sends FCM web-push notifications to a restaurant's registered admin devices.
 *
 * Entirely best-effort: if Firebase credentials aren't configured yet, or a
 * send fails, it logs and returns — it must never break the flow that calls it
 * (order recording, review submission…). Invalid/expired tokens reported by FCM
 * are pruned. Prefer routing through NotificationService, which records the
 * durable notification and then fans out here.
 */
class PushService
{
    /**
     * Fan a push out to every device registered for the restaurant.
     *
     * @param  array<string,mixed>  $data  extra payload merged into the message
     * @param  string  $link  where a click on the notification lands
     */
    public function toRestaurant(int $restaurantId, string $title, string $body, array $data = [], string $link = '/admin'): void
    {
        $tokens = DeviceToken::where('restaurant_id', $restaurantId)->pluck('token')->all();
        if ($tokens === []) {
            return;
        }

        try {
            $messaging = app(Messaging::class);
        } catch (\Throwable $e) {
            Log::info('FCM not configured; skipping push', ['error' => $e->getMessage()]);

            return;
        }

        $message = CloudMessage::new()
            ->withNotification(FcmNotification::create($title, $body))
            ->withData(array_map('strval', $data) + ['url' => $link])
            ->withWebPushConfig(WebPushConfig::fromArray([
                'notification' => ['requireInteraction' => true],
                'fcm_options' => ['link' => $link],
            ]));

        try {
            $report = $messaging->sendMulticast($message, $tokens);

            foreach ([...$report->invalidTokens(), ...$report->unknownTokens()] as $dead) {
                DeviceToken::where('token', $dead)->delete();
            }
        } catch (\Throwable $e) {
            Log::warning('FCM send failed', ['error' => $e->getMessage()]);
        }
    }
}
