<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A device that has used a licence's activation key: first and last time seen,
 * and how many times. See the migration for why it is keyed on the key's HMAC.
 *
 * Platform-level data (no tenant scope), read only through the Super Admin
 * licence endpoints.
 */
class PosLicenceActivation extends Model
{
    protected $fillable = ['key_hash', 'fingerprint', 'first_seen_at', 'last_seen_at', 'times'];

    protected function casts(): array
    {
        return [
            'first_seen_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'times' => 'integer',
        ];
    }
}
