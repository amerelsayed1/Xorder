<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Writes {@see AuditLog} rows. Actor and request context are resolved
 * automatically; callers only describe *what* happened.
 *
 * Auditing must never break the operation it records, so every write is
 * defensive: a failure is logged and swallowed, not thrown.
 */
class AuditLogger
{
    /**
     * Record an event.
     *
     * @param  string  $action  Dotted key, e.g. "restaurant.status_changed".
     * @param  array{
     *     restaurant_id?: int|null,
     *     actor?: User|null,
     *     actor_role?: string|null,
     *     auditable?: Model|null,
     *     description?: string|null,
     *     properties?: array<string,mixed>|null,
     * }  $opts
     */
    public static function record(string $action, array $opts = []): ?AuditLog
    {
        try {
            $actor = $opts['actor'] ?? self::currentActor();
            $auditable = $opts['auditable'] ?? null;
            $request = request();

            $actorRole = $opts['actor_role'] ?? self::resolveActorRole($actor);
            $actorName = $actor?->name ?? ($actorRole === 'CUSTOMER' ? 'Customer' : null);

            // Honour an explicitly-provided restaurant_id even when it is null
            // (e.g. a tenant-root deletion is intentionally platform-scoped);
            // only auto-resolve when the caller didn't supply the key at all.
            $restaurantId = array_key_exists('restaurant_id', $opts)
                ? $opts['restaurant_id']
                : self::resolveRestaurantId($actor, $auditable);

            return AuditLog::create([
                'restaurant_id' => $restaurantId,
                'actor_id' => $actor?->getKey(),
                'actor_name' => $actorName,
                'actor_role' => $actorRole,
                'action' => $action,
                'auditable_type' => $auditable ? $auditable->getMorphClass() : null,
                'auditable_id' => $auditable?->getKey(),
                'description' => $opts['description'] ?? null,
                'properties' => $opts['properties'] ?? null,
                'ip_address' => $request?->ip(),
                'user_agent' => $request?->userAgent(),
            ]);
        } catch (Throwable $e) {
            Log::warning('Audit log write failed', ['action' => $action, 'error' => $e->getMessage()]);

            return null;
        }
    }

    private static function currentActor(): ?User
    {
        $user = Auth::user();

        return $user instanceof User ? $user : null;
    }

    private static function resolveActorRole(?User $actor): ?string
    {
        if (! $actor) {
            return null;
        }

        return $actor->role instanceof \BackedEnum ? $actor->role->value : (string) $actor->role;
    }

    /** Best-effort tenant scope: the actor's restaurant, else the subject's. */
    private static function resolveRestaurantId(?User $actor, ?Model $auditable): ?int
    {
        if ($actor && $actor->restaurant_id) {
            return $actor->restaurant_id;
        }

        if ($auditable) {
            if (method_exists($auditable, 'auditRestaurantId')) {
                return $auditable->auditRestaurantId();
            }
            if (isset($auditable->restaurant_id)) {
                return $auditable->restaurant_id;
            }
        }

        return null;
    }
}
