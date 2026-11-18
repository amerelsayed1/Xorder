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

    /*
    |--------------------------------------------------------------------------
    | Default phone country
    |--------------------------------------------------------------------------
    | ISO-3166 alpha-2 region used to parse phone numbers written in local
    | format (e.g. Egyptian "01xxxxxxxxx"). Numbers written in international
    | E.164 format ("+9665...") are validated against their own country's
    | rules regardless of this default. Set to the platform's primary market.
    */
    'default_phone_country' => env('PLATFORM_DEFAULT_COUNTRY', 'EG'),

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

    /*
    |--------------------------------------------------------------------------
    | Presence signals
    |--------------------------------------------------------------------------
    | Tuning for the learned "is this diner on the branch's Wi-Fi?" check
    | (BranchEgressIpService). A browser cannot read the Wi-Fi network it is
    | joined to, so the only available signal is the public address the request
    | arrived from — learned from geofence-verified sessions rather than
    | configured by the restaurant.
    */
    'presence' => [
        /*
        | TEMPORARY — on-site presence enforcement is switched OFF.
        |
        | Hardcoded rather than env-driven on purpose: this is a deliberate
        | product decision that must behave identically everywhere, not
        | something a machine's .env can silently differ on. Flip to true to
        | restore the geofence; nothing else needs changing.
        |
        | While false: a table QR scan never asks for GPS and is never refused
        | for being out of area, and the dashboard hides the branch geofence
        | editor. Note that branch Wi-Fi addresses can then only be declared by
        | hand — automatic learning needs geofence-verified sessions to trust.
        */
        'geofence_enforcement' => false,

        // Rolling window of verified sessions the addresses are derived from.
        // Short enough that a rotated dynamic IP ages out on its own.
        'egress_learning_days' => env('PRESENCE_EGRESS_LEARNING_DAYS', 30),

        // Verified sessions an address needs before it counts as the branch's.
        // Keeps a single coincidental carrier IP from being learned.
        'egress_min_sessions' => env('PRESENCE_EGRESS_MIN_SESSIONS', 5),

        // Cap per branch, so a line that rotates often can hold its recent
        // addresses without accumulating an unbounded tail.
        'egress_max_ips' => env('PRESENCE_EGRESS_MAX_IPS', 5),

        /*
        | Drift detection — noticing that a branch's line has changed address.
        |
        | A declared address goes stale silently when a dynamic line rotates:
        | the card keeps reporting "recognised" while matching nobody. So we
        | watch where that branch's own table scans actually come from, and when
        | one unfamiliar address dominates, surface it for the owner to confirm.
        |
        | Deliberately a suggestion, never an automatic switch. Table scans are
        | not proof of presence on their own, so promoting whichever address
        | happens to dominate would be a way in for anyone patient enough. A
        | human confirms; the machine only points.
        */
        'egress_drift_min_sessions' => 5,
        'egress_drift_min_share' => 60, // percent of the branch's scans
    ],

    // Cooldown before the same session can raise another bill request (FR-BILL-009).
    'bill_request_cooldown_seconds' => env('BILL_REQUEST_COOLDOWN_SECONDS', 120),

    // A private review with a rating at or below this threshold is "low" — it is
    // flagged in the dashboard and counted separately (Phase 3).
    'review_low_rating_threshold' => env('REVIEW_LOW_RATING_THRESHOLD', 3),

    /*
    |--------------------------------------------------------------------------
    | Guest paging (docs/features/guest-paging)
    |--------------------------------------------------------------------------
    | call_out_minutes: a READY order nobody acknowledged for this long gets
    | the board's "Call it out" badge. tracking_ttl_hours: how long a receipt's
    | tracking link keeps resolving after the order was placed.
    */
    'guest_paging' => [
        'call_out_minutes' => env('GUEST_PAGING_CALL_OUT_MINUTES', 3),
        'tracking_ttl_hours' => env('GUEST_PAGING_TRACKING_TTL_HOURS', 48),
        // Shared-QR pairing (docs/features/guest-paging-shared-qr): the code a
        // client reads out to the cashier, and how long it stays open.
        'pairing_code_digits' => env('GUEST_PAGING_PAIRING_CODE_DIGITS', 4),
        'pairing_ttl_minutes' => env('GUEST_PAGING_PAIRING_TTL_MINUTES', 30),
    ],

    /*
    |--------------------------------------------------------------------------
    | Report day-part periods (Phase 4 — Product Analytics)
    |--------------------------------------------------------------------------
    | Ordered windows used to bucket each order into a "time of day" for the
    | products-by-time report (FR-REPORT-005). Times are local to the
    | restaurant's timezone (restaurant.timezone ?? app.timezone). The last
    | window wraps past midnight (22:00 -> 02:00); orders that fall outside
    | every window land in a synthetic "other" bucket. "afternoon" is folded
    | into lunch to keep the windows contiguous and non-overlapping.
    */
    // Largest date span (in days) a single product-analytics report may query,
    // bounding in-memory aggregation. Requests beyond this are rejected (422).
    'report_max_range_days' => env('REPORT_MAX_RANGE_DAYS', 366),

    'report_periods' => [
        ['key' => 'breakfast', 'from' => '08:00', 'to' => '12:00'],
        ['key' => 'lunch', 'from' => '12:00', 'to' => '17:00'],
        ['key' => 'dinner', 'from' => '17:00', 'to' => '22:00'],
        ['key' => 'late_night', 'from' => '22:00', 'to' => '02:00'],
    ],

    'super_admin' => [
        'name' => env('SUPER_ADMIN_NAME', 'Super Admin'),
        'username' => env('SUPER_ADMIN_USERNAME', 'admin'),
        'email' => env('SUPER_ADMIN_EMAIL', 'admin@qrmenu.test'),
        // No fallback: the seeder fails closed if SUPER_ADMIN_PASSWORD is unset,
        // so production can never provision the platform admin with a default
        // credential. Set a strong value in the environment.
        'password' => env('SUPER_ADMIN_PASSWORD'),
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
        'mimes' => ['jpg', 'jpeg', 'png', 'webp', 'avif'],
        'max_dimension' => 2000,
    ],

    /*
    |--------------------------------------------------------------------------
    | Activity log file
    |--------------------------------------------------------------------------
    | Every audit event is mirrored into a per-day file via the "activity" log
    | channel (storage/logs/activity-Y-m-d.log) on top of the audit_logs table,
    | so the trail can be tailed/grepped on the box. Set ACTIVITY_LOG_FILE=false
    | to keep the DB trail only; ACTIVITY_LOG_DAYS controls retention.
    */
    'activity_log_file' => env('ACTIVITY_LOG_FILE', true),

    /*
    |--------------------------------------------------------------------------
    | Audit trail retention
    |--------------------------------------------------------------------------
    | Legacy only. Nothing writes to audit_logs any more — the daily activity
    | files are the system of record — but `audit:prune` still trims whatever
    | history predates the switch. Retention for what the audit screen actually
    | reads is ACTIVITY_LOG_DAYS on the "activity" log channel.
    */
    'audit_log_days' => env('AUDIT_LOG_DAYS', 90),

];
