<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use DateTimeInterface;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A waiter's working shift (POS-BE-033 shift clock). Belongs to the user, not
 * the phone: a waiter who starts on one device and finishes on another has one
 * shift. At most one is open per user (partial unique index on ended_at null).
 *
 * Tenant-scoped by RestaurantScope; the wire pins the tenant from the slug and
 * every query here also names the restaurant explicitly.
 */
class PosWaiterShift extends Model
{
    use BelongsToRestaurant;

    protected $guarded = [];

    protected function casts(): array
    {
        return ['started_at' => 'datetime', 'ended_at' => 'datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function startedDevice(): BelongsTo
    {
        return $this->belongsTo(PosWaiterDevice::class, 'started_device_id');
    }

    public function endedDevice(): BelongsTo
    {
        return $this->belongsTo(PosWaiterDevice::class, 'ended_device_id');
    }

    public function isOpen(): bool
    {
        return $this->ended_at === null;
    }

    /**
     * The wire shape, as the Dart `WaiterShift.toJson` writes it: UTC with
     * milliseconds and a `Z`; `ended_at` omitted while the shift is open.
     *
     * @return array{id: int, started_at: string, ended_at?: string}
     */
    public function toWire(): array
    {
        return [
            'id' => $this->id,
            'started_at' => self::wireTime($this->started_at),
        ] + ($this->ended_at !== null ? ['ended_at' => self::wireTime($this->ended_at)] : []);
    }

    private static function wireTime(DateTimeInterface $at): string
    {
        return Carbon::instance($at)->utc()->format('Y-m-d\TH:i:s.v\Z');
    }
}
