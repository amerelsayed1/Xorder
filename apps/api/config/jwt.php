<?php

return [

    /*
    |--------------------------------------------------------------------------
    | JWT signing secret
    |--------------------------------------------------------------------------
    |
    | Symmetric key used to sign and verify API access tokens (HS256). Keep it
    | out of source control — set JWT_SECRET in the environment. Rotating it
    | invalidates every issued token at once.
    |
    */

    'secret' => env('JWT_SECRET'),

    /*
    |--------------------------------------------------------------------------
    | Token lifetime (minutes)
    |--------------------------------------------------------------------------
    |
    | How long an access token stays valid after it is issued. Tokens are
    | stateless, so this TTL is the only bound on a leaked token's usefulness —
    | keep it modest. Defaults to 7 days.
    |
    */

    'ttl' => (int) env('JWT_TTL', 60 * 24 * 7),

    /*
    |--------------------------------------------------------------------------
    | Signing algorithm
    |--------------------------------------------------------------------------
    */

    'algo' => env('JWT_ALGO', 'HS256'),

];
