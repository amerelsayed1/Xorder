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
     * The restaurant's own "today".
     *
     * Views must bucket by the diner's local day, not the server's: on a UTC
     * server an Egyptian restaurant (UTC+3) would roll over at 3am local, so a
     * busy Friday evening would spill its last hours into Saturday. Reports and
     * category availability already resolve the day this way — this keeps the
     * views chart agreeing with the orders chart beside it.
     */
    public static function todayFor(int $restaurantId): string
    {
        $restaurant = Restaurant::withoutGlobalScopes()->find($restaurantId);

        return $restaurant?->today() ?? now(config('app.timezone', 'UTC'))->toDateString();
    }

    /**
     * Count one public menu view for today. Concurrent first-views race on
     * the unique (restaurant_id, date) key — the loser retries the UPDATE.
     */
    public static function record(int $restaurantId): void
    {
        $today = self::todayFor($restaurantId);

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
