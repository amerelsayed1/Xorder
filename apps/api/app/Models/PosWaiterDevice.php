<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A waiter's phone (POS-BE-033). Created by its first sign-in; the token is
 * shown once and kept only as an HMAC. Always queried with an explicit
 * restaurant_id: the wire resolves the tenant from the slug first.
 */
class PosWaiterDevice extends Model
{
    protected $guarded = [];

    protected $hidden = ['token_hash'];

    protected function casts(): array
    {
        return ['last_seen_at' => 'datetime', 'revoked_at' => 'datetime'];
    }

    public function isRevoked(): bool
    {
        return $this->revoked_at !== null;
    }
}
