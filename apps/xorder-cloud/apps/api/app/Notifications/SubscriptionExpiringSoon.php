<?php

namespace App\Notifications;

use App\Models\Restaurant;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class SubscriptionExpiringSoon extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Restaurant $restaurant,
        public readonly int $daysRemaining,
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $name = $this->restaurant->name_en ?: $this->restaurant->name_ar;

        return (new MailMessage)
            ->subject("Your subscription expires in {$this->daysRemaining} day(s)")
            ->greeting("Hello, {$notifiable->name}!")
            ->line("The subscription for {$name} ends on {$this->restaurant->subscription_end_date?->toDateString()}.")
            ->line('After that date the dashboard becomes read-only until the subscription is renewed.')
            ->action('Open Dashboard', rtrim(config('app.url'), '/').'/login')
            ->line('Contact us to renew and keep your menu fully manageable.');
    }
}
