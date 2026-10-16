<?php

namespace App\Services;

use App\Models\PosTerminal;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Records events into the per-day activity file (storage/logs/activity-Y-m-d.log,
 * the "activity" log channel) — one JSON object per line. Actor and request
 * context are resolved automatically; callers only describe *what* happened.
 *
 * The file is the only sink: {@see ActivityLogReader} parses it back for the
 * audit screens, so there is no database table to keep in step. Auditing must
 * never break the operation it records, so the write is defensive — a failure
 * is logged and swallowed, not thrown.
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
    public static function record(string $action, array $opts = []): void
    {
        try {
            $data = self::buildRow($action, $opts);
        } catch (Throwable $e) {
            Log::warning('Audit log build failed', ['action' => $action, 'error' => $e->getMessage()]);

            return;
        }

        self::writeToActivityFile($data);
    }

    /**
     * Resolve the actor/tenant/request context into the row both sinks share.
     *
     * @param  array<string,mixed>  $opts
     * @return array<string,mixed>
     */
    private static function buildRow(string $action, array $opts): array
    {
        $actor = $opts['actor'] ?? self::currentActor();
        $auditable = $opts['auditable'] ?? null;
        $request = request();

        $actorRole = $opts['actor_role'] ?? self::resolveActorRole($actor);
        $actorName = $actor?->name ?? ($actorRole === 'CUSTOMER' ? 'Customer' : null);

        // A till's write: no authenticated user (device auth is a PosTerminal,
        // not an Authenticatable), but the request knows which terminal and —
        // when the payload named one — which cashier. Read as the terminal and
        // the acting staff member rather than as nobody or as "Customer" (the
        // Order's diner fallback, S4-1). TERMINAL is the role the POS services
        // already stamp by hand on their own rows; those rows get the name too.
        $terminalRole = ! isset($opts['actor_role']) || $opts['actor_role'] === 'TERMINAL';
        if ($actor === null && $terminalRole && ($terminal = self::requestTerminal()) !== null) {
            $staff = self::requestActingUser();
            $actor = $staff;
            $actorRole = 'TERMINAL';
            $actorName = $staff ? $terminal->name.' · '.$staff->name : $terminal->name;
        }

        // Honour an explicitly-provided restaurant_id even when it is null
        // (e.g. a tenant-root deletion is intentionally platform-scoped);
        // only auto-resolve when the caller didn't supply the key at all.
        $restaurantId = array_key_exists('restaurant_id', $opts)
            ? $opts['restaurant_id']
            : self::resolveRestaurantId($actor, $auditable);

        return [
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
        ];
    }

    /**
     * Append the event to today's activity file as one JSON object.
     *
     * The key order is FIXED and load-bearing: {@see ActivityLogReader} filters
     * and counts by matching substrings like `"tenant_id":7,` against the raw
     * line, which lets it page through a month of history without decoding
     * every event. Reordering or dropping a key breaks that fast path.
     *
     * @param  array<string,mixed>  $data
     */
    private static function writeToActivityFile(array $data): void
    {
        if (! config('platform.activity_log_file', true)) {
            return;
        }

        try {
            $line = json_encode([
                'ts' => now()->toIso8601String(),
                'action' => $data['action'],
                'tenant_id' => $data['restaurant_id'],
                'actor_id' => $data['actor_id'],
                'actor_name' => $data['actor_name'],
                'actor_role' => $data['actor_role'],
                'subject_type' => $data['auditable_type'] ? class_basename($data['auditable_type']) : null,
                'subject_id' => $data['auditable_id'],
                'ip' => $data['ip_address'],
                'description' => $data['description'],
                'properties' => $data['properties'] ?: null,
            ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

            // A newline inside a description would split one event across two
            // lines and break the one-JSON-object-per-line contract.
            Log::channel('activity')->info(str_replace(["\r", "\n"], ' ', (string) $line));
        } catch (Throwable $e) {
            Log::warning('Activity file write failed', [
                'action' => $data['action'] ?? null,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private static function currentActor(): ?User
    {
        $user = Auth::user();

        return $user instanceof User ? $user : null;
    }

    /**
     * The terminal behind the current request, when it is a till's
     * (PosDeviceAuth sets it); null on every other path.
     */
    public static function requestTerminal(): ?PosTerminal
    {
        $terminal = request()?->attributes->get('pos_terminal');

        return $terminal instanceof PosTerminal ? $terminal : null;
    }

    /**
     * The cashier a till's request acts for, once the service resolved the
     * payload's acting_user_id ({@see attachPosActingUser}); null when the
     * till named nobody (v1's terminal-only attribution).
     */
    public static function requestActingUser(): ?User
    {
        $user = request()?->attributes->get('pos_acting_user');

        return $user instanceof User ? $user : null;
    }

    /**
     * Called by the POS services as soon as they have verified the acting
     * staff member, so every audit row the rest of the request writes carries
     * the cashier's name next to the terminal's. Verified first, never raw:
     * an unknown or foreign acting_user_id is refused before it gets here.
     */
    public static function attachPosActingUser(?User $user): void
    {
        if ($user !== null) {
            request()?->attributes->set('pos_acting_user', $user);
        }
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
