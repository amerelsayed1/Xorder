<?php

use App\Enums\SubscriptionStatus;

return [

    /*
    |--------------------------------------------------------------------------
    | Super Admin bootstrap credentials
    |--------------------------------------------------------------------------
    | Used by DatabaseSeeder to provision the single platform Super Admin.
    | Set real values in .env for any non-local environment.
    */
    /*
    |--------------------------------------------------------------------------
    | Public menu domain
    |--------------------------------------------------------------------------
    | When set (e.g. "tryorder.net"), each restaurant's public menu lives on
    | its own subdomain: https://{slug}.tryorder.net/menu. Requires a wildcard
    | DNS record (*.tryorder.net) and a wildcard TLS certificate. Leave null
    | for local/dev, where menus are served at /r/{slug} instead.
    */
    'menu_domain' => env('MENU_DOMAIN'),
    'menu_secure' => env('MENU_SECURE', true),
    'menu_port' => env('MENU_PORT'), // e.g. 8080 for local; unset on standard 80/443

    // Slugs that would collide with system subdomains — never assignable.
    'reserved_slugs' => [
        'www', 'app', 'api', 'admin', 'dashboard', 'mail', 'ftp', 'cdn',
        'assets', 'static', 'menu', 'qr', 'support', 'help', 'status',
    ],

    'super_admin' => [
        'name' => env('SUPER_ADMIN_NAME', 'Super Admin'),
        'email' => env('SUPER_ADMIN_EMAIL', 'admin@qrmenu.test'),
        'password' => env('SUPER_ADMIN_PASSWORD', 'password'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Subscription gating
    |--------------------------------------------------------------------------
    | hide_menu_when_expired:
    |   false (default) -> EXPIRED restaurants keep a public menu, but the
    |                      dashboard becomes read-only (writes are blocked).
    |   true            -> EXPIRED behaves like SUSPENDED: the public menu
    |                      shows the "currently unavailable" page.
    |
    | Status-driven public visibility (ACTIVE only) is always enforced; this
    | flag only governs the subscription dimension.
    */
    'subscription' => [
        'hide_menu_when_expired' => env('HIDE_MENU_WHEN_EXPIRED', false),
        'enforce_dashboard_writes' => env('ENFORCE_SUBSCRIPTION_WRITES', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Image uploads
    |--------------------------------------------------------------------------
    */
    'uploads' => [
        'disk' => env('UPLOAD_DISK', 'public'),
        'max_kb' => 4096,
        'mimes' => ['jpg', 'jpeg', 'png', 'webp'],
        'max_dimension' => 2000,
    ],

];
