<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Emails a platform staff user (Admin/Moderator/Sales/Support) their initial or
 * reset dashboard credentials. Mirrors {@see RestaurantAdminCredentials} but is
 * platform-scoped (no restaurant).
 */
class PlatformUserCredentials extends Notification
{
    use Queueable;

    public function __construct(
        public readonly string $password,
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your Xorder admin access')
            ->greeting("Welcome, {$notifiable->name}!")
            ->line('An administrator account has been created for you on the Xorder platform.')
            ->line("Email: {$notifiable->email}")
            ->line("Username: {$notifiable->username}")
            ->line("Temporary password: {$this->password}")
            ->action('Open Dashboard', rtrim(config('app.url'), '/').'/login')
            ->line('Please change your password after your first login.');
    }
}
