<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * A durable dashboard notification. Tenant-scoped via BelongsToRestaurant, so
 * dashboard reads only ever see the signed-in restaurant's feed and public
 * writers (which set restaurant_id explicitly) reach the right tenant even with
 * no resolved TenantContext.
 *
 * Deliberately not Auditable: notifications are system-generated noise and
 * logging their creation would only clutter the audit trail.
 */
class Notification extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'type',
        'title',
        'body',
        'data',
        'read_at',
    ];

    protected function casts(): array
    {
        return [
            'data' => 'array',
            'read_at' => 'datetime',
        ];
    }

    public function isRead(): bool
    {
        return $this->read_at !== null;
    }

    /**
     * The capability that lets a staff member see each kind of notification: the
     * same one that opens the screen the notification points at. The owner holds
     * every capability. A kind that is not listed here (subscription notices, or
     * one added later and not yet mapped) is shown to the owner only, so a new
     * kind fails closed instead of leaking to every role.
     *
     * @var array<string, string>
     */
    public const CAPABILITY_BY_TYPE = [
        'order.created' => 'orders.view',
        'bill_request.created' => 'bills.view',
        'review.created' => 'reviews.view',
    ];

    /** May this account see a notification of this kind? */
    public static function typeVisibleTo(string $type, User $user): bool
    {
        if ($user->isRestaurantAdmin()) {
            return true;
        }

        $capability = self::CAPABILITY_BY_TYPE[$type] ?? null;

        return $capability !== null && $user->can($capability);
    }

    /**
     * Limit a query to the notifications this account may see. Apply it to every
     * read, count and update so the feed, the badge, the pulse and mark-read all
     * agree.
     */
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        if ($user->isRestaurantAdmin()) {
            return $query;
        }

        $types = array_keys(array_filter(
            self::CAPABILITY_BY_TYPE,
            fn (string $capability) => $user->can($capability),
        ));

        // whereIn with an empty list matches nothing, which is the intent.
        return $query->whereIn('type', $types);
    }
}
