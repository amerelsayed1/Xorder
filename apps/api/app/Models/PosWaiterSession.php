<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** One signed-in waiter on one device (POS-BE-033). Idles out after IDLE_HOURS. */
class PosWaiterSession extends Model
{
    public const IDLE_HOURS = 12;

    protected $guarded = [];

    protected $hidden = ['token_hash'];

    protected function casts(): array
    {
        return ['last_seen_at' => 'datetime'];
    }
}
