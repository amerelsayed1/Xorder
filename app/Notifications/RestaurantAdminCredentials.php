<?php

namespace App\Notifications;

use App\Models\Restaurant;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class RestaurantAdminCredentials extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Restaurant $restaurant,
        public readonly string $password,
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your QR Menu dashboard access')
            ->greeting("Welcome, {$notifiable->name}!")
            ->line("A dashboard has been created for {$this->restaurant->name_en}.")
            ->line("Email: {$notifiable->email}")
            ->line("Temporary password: {$this->password}")
            ->action('Open Dashboard', rtrim(config('app.url'), '/') . '/login')
            ->line('Please change your password after your first login.');
    }
}
