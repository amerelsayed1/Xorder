<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class DiningTable extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'branch_id',
        'dining_area_id',
        'label',
        'seats_count',
        'notes',
        'public_token',
        'is_active',
        'qr_generated_at',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'seats_count' => 'integer',
            'qr_generated_at' => 'datetime',
        ];
    }

    /**
     * A non-sequential, platform-unique token for the QR URL (BR-003/004).
     * Uppercase alphanumerics without look-alikes (no 0/O, 1/I) so a token
     * printed on a table card is easy to read back.
     */
    public static function generateToken(int $length = 10): string
    {
        $alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
        $max = strlen($alphabet) - 1;

        do {
            $token = '';
            for ($i = 0; $i < $length; $i++) {
                $token .= $alphabet[random_int(0, $max)];
            }
        } while (static::withoutGlobalScopes()->where('public_token', $token)->exists());

        return $token;
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function diningArea(): BelongsTo
    {
        return $this->belongsTo(DiningArea::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class, 'table_id');
    }

    /** The public menu URL the QR encodes for this table. */
    public function publicUrl(): string
    {
        return $this->restaurant->tableUrl($this->public_token);
    }
}
