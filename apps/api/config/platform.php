<?php

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

    // Built guest-menu SPA entry (apps/menu). MenuShellService injects the
    // per-restaurant SEO tags into this file when serving /menu. Leave unset
    // to use the Docker/monorepo default locations.
    'menu_shell_path' => env('MENU_SHELL_PATH'),

    // Slugs that would collide with system subdomains — never assignable.
    'reserved_slugs' => [
        'www', 'app', 'api', 'admin', 'dashboard', 'mail', 'ftp', 'cdn',
        'assets', 'static', 'menu', 'qr', 'support', 'help', 'status',
    ],

    /*
    |--------------------------------------------------------------------------
    | Self-serve signup
    |--------------------------------------------------------------------------
    | OFF by default: the platform launches sales-led (landing → leads inbox →
    | manual provisioning). Flip SELF_SERVE_SIGNUP=true to open
    | POST /api/public/signup, which provisions a restaurant + admin with a
    | TRIAL subscription automatically.
    */
    'self_serve_signup' => env('SELF_SERVE_SIGNUP', false),
    'signup_trial_days' => env('SIGNUP_TRIAL_DAYS', 14),

    // How long a table menu session stays valid without activity (FR-SESSION-009).
    'table_session_ttl_minutes' => env('TABLE_SESSION_TTL_MINUTES', 240),

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
