<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\QueryException;

class MenuViewDaily extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'date',
        'views',
    ];

    protected function casts(): array
    {
        return [
            'date' => 'date',
        ];
    }

    /**
     * Count one public menu view for today. Concurrent first-views race on
     * the unique (restaurant_id, date) key — the loser retries the UPDATE.
     */
    public static function record(int $restaurantId): void
    {
        $today = now()->toDateString();

        $updated = static::withoutGlobalScopes()
            ->where('restaurant_id', $restaurantId)
            ->whereDate('date', $today)
            ->increment('views');

        if ($updated === 0) {
            try {
                $row = new static(['date' => $today, 'views' => 1]);
                $row->restaurant_id = $restaurantId;
                $row->save();
            } catch (QueryException) {
                static::withoutGlobalScopes()
                    ->where('restaurant_id', $restaurantId)
                    ->whereDate('date', $today)
                    ->increment('views');
            }
        }
    }
}
