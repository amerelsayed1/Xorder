<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A single-use, 24h claim credential for one provisioned terminal
 * (POS-BE-023). Only the HMAC is stored; response_cache holds the ENCRYPTED
 * claim response so a timed-out claim replaying the same code from the same
 * device gets byte-identical bytes back — including the device token — instead
 * of a second terminal. Purged when the code expires.
 */
class PosPairingCode extends Model
{
    use BelongsToRestaurant;

    /** Nothing here is mass-assignable; the provisioning service forceFills. */
    protected $fillable = [];

    protected $hidden = ['code_hash', 'response_cache'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'used_at' => 'datetime',
        ];
    }

    public function terminal(): BelongsTo
    {
        return $this->belongsTo(PosTerminal::class, 'pos_terminal_id');
    }

    public function isExpired(): bool
    {
        return $this->expires_at->isPast();
    }
}
