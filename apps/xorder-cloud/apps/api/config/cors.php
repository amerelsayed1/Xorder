<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | The SPA (apps/web) and landing (apps/landing) are decoupled and call this
    | API from a different origin. Auth is a stateless JWT Bearer token, so
    | credentialed (cookie) requests are not required — but origins are still
    | listed explicitly so the browser permits the cross-origin XHR.
    |
    | Set CORS_ALLOWED_ORIGINS in .env to a comma-separated list of frontend
    | origins, e.g. https://app.tryorder.net,https://xorder.net
    |
    */

    'paths' => ['api/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('CORS_ALLOWED_ORIGINS', 'http://localhost:5173,http://localhost:5174'))
    ))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    // Auth travels in the Authorization header, not cookies, so credentialed
    // (cookie-bearing) cross-origin requests are no longer needed.
    'supports_credentials' => false,

];
