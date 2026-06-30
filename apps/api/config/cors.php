<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | The SPA (apps/web) and landing (apps/landing) are decoupled and call this
    | API from a different origin. For Sanctum cookie auth to work, CORS must
    | allow credentials, and the allowed origins must be listed explicitly
    | (a wildcard "*" is not permitted alongside credentialed requests).
    |
    | Set CORS_ALLOWED_ORIGINS in .env to a comma-separated list of frontend
    | origins, e.g. https://app.tryorder.net,https://xorder.net
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie', 'login', 'logout'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('CORS_ALLOWED_ORIGINS', 'http://localhost:5173,http://localhost:5174'))
    ))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => true,

];
