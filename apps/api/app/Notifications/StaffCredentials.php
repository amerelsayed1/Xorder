<?php

namespace App\Notifications;

use App\Models\Restaurant;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Emails a restaurant staff account its initial or reset dashboard credentials.
 * Staff may be created without an email (username-only logins for floor staff),
 * in which case the mail channel has no route and simply no-ops — the plaintext
 * password is returned to the caller once so the manager can hand it over.
 */
class StaffCredentials extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Restaurant $restaurant,
        public readonly string $password,
    ) {}

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Your dashboard access')
            ->greeting("Welcome, {$notifiable->name}!")
            ->line("A staff account has been created for you at {$this->restaurant->name_en}.")
            ->line("Username: {$notifiable->username}")
            ->line("Temporary password: {$this->password}")
            ->action('Open Dashboard', rtrim(config('app.url'), '/').'/login')
            ->line('Please change your password after your first login.');
    }
}
