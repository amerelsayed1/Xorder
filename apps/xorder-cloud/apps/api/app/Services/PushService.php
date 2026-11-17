<?php

namespace App\Services;

use App\Models\DeviceToken;
use App\Models\Notification;
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
     * The device tokens a push of this kind may go to: those whose user may see
     * that kind of notification (the same rule as the in-app feed). A push with
     * no kind is untyped and goes to the owner's devices only, so nothing leaks
     * by default. Tokens whose user no longer exists are skipped.
     *
     * @return list<string>
     */
    public function tokensFor(int $restaurantId, ?string $type): array
    {
        return DeviceToken::query()
            ->where('restaurant_id', $restaurantId)
            ->with('user.tenantRole')
            ->get()
            ->filter(fn (DeviceToken $t) => $t->user !== null
                && Notification::typeVisibleTo($type ?? '', $t->user))
            ->pluck('token')
            ->values()
            ->all();
    }

    /**
     * Fan a push out to every device registered for the restaurant.
     *
     * @param  array<string,mixed>  $data  extra payload merged into the message
     * @param  string  $link  where a click on the notification lands
     */
    public function toRestaurant(int $restaurantId, string $title, string $body, array $data = [], string $link = '/admin'): void
    {
        $tokens = $this->tokensFor($restaurantId, isset($data['type']) ? (string) $data['type'] : null);
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
