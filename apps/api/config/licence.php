<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Ed25519 signing key
    |--------------------------------------------------------------------------
    |
    | Base64 of the 64-byte libsodium secret key that signs POS licence files.
    | Generate with:
    |
    |   php artisan licence:keygen
    |
    | This key never leaves the issuer — not to a branch server, not to a till,
    | not into an audit row. Without it, issuance fails loudly; activation of
    | already-minted licences keeps working, because the signed artifact is
    | stored rather than re-signed on demand.
    |
    */
    'signing_key' => env('LICENCE_SIGNING_KEY'),

    /*
    |--------------------------------------------------------------------------
    | Key id
    |--------------------------------------------------------------------------
    |
    | Names the key pair a licence was signed with, so a pair can be rotated
    | without invalidating everything already issued.
    |
    | ROTATION RULE — the one that can strand a fleet: ship the new PUBLIC key
    | in a POS release BEFORE signing anything with it. A till that cannot
    | verify has no way of being told to update; it reports `invalid`, which the
    | operator reads as "my licence is broken". Keep signing with the old key_id
    | until the fleet is confirmed on the new build.
    |
    */
    'key_id' => env('LICENCE_KEY_ID', 'v1'),

    /*
    |--------------------------------------------------------------------------
    | Defaults for a newly issued licence
    |--------------------------------------------------------------------------
    |
    | grace_days is deliberately generous: the cost of a wrongly-blocked till is
    | far higher than a fortnight of unpaid use. See docs/pos/09-licensing.md.
    |
    */
    'defaults' => [
        'grace_days' => 14,
        'warn_days' => 30,
        'max_terminals' => 1,
    ],

];
