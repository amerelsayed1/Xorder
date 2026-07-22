<?php

namespace App\Models\Concerns;

use App\Services\AuditLogger;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;

/**
 * Automatically records created / updated / deleted events for a model into the
 * audit log. Opt in by `use Auditable;` on the model.
 *
 * Override points:
 *  - $auditExclude          extra attributes to omit from change diffs
 *  - auditActionPrefix()    dotted action namespace (default: snake_case class)
 *  - auditRestaurantId()    tenant scope (default: $this->restaurant_id)
 *  - auditActorRoleFallback() role to stamp when no user is authenticated
 *                             (e.g. Order → 'CUSTOMER' for diner-placed orders)
 */
trait Auditable
{
    public static function bootAuditable(): void
    {
        static::created(fn ($model) => $model->recordAuditEvent('created'));
        static::updated(fn ($model) => $model->recordAuditEvent('updated'));
        static::deleted(fn ($model) => $model->recordAuditEvent('deleted'));
    }

    protected function recordAuditEvent(string $event): void
    {
        $properties = null;

        if ($event === 'updated') {
            $changes = $this->auditChanges();
            if (empty($changes)) {
                return; // no auditable attribute actually changed
            }
            $properties = ['changes' => $changes];
        }

        // A tenant-root deleting itself (a Restaurant): by the time the delete
        // fires, its row is gone, so a restaurant_id FK back to it would dangle
        // and abort the transaction. Scope that one record to the platform
        // (null) — the id is still preserved in auditable_id, which has no FK.
        $restaurantId = $this->auditRestaurantId();
        if ($event === 'deleted' && $this->auditIsTenantRoot()) {
            $restaurantId = null;
        }

        $opts = [
            'restaurant_id' => $restaurantId,
            'auditable' => $this,
            'description' => $this->auditDescription($event),
            'properties' => $properties,
        ];

        // Diner-driven writes (e.g. an order placed on the public menu) have no
        // authenticated user; stamp the fallback role so they read as "Customer".
        if (! Auth::check() && ($role = $this->auditActorRoleFallback())) {
            $opts['actor_role'] = $role;
        }

        AuditLogger::record($this->auditActionPrefix().'.'.$event, $opts);
    }

    protected function auditActionPrefix(): string
    {
        return Str::snake(class_basename(static::class));
    }

    public function auditRestaurantId(): ?int
    {
        return $this->restaurant_id ?? null;
    }

    /**
     * Whether this model IS the tenant (a Restaurant) rather than a row owned
     * by one. Tenant-root deletions can't reference themselves via the
     * restaurant_id FK, so the trait nulls that column for them.
     */
    protected function auditIsTenantRoot(): bool
    {
        return false;
    }

    protected function auditActorRoleFallback(): ?string
    {
        return null;
    }

    /**
     * @return array<string, array{old: mixed, new: mixed}>
     */
    protected function auditChanges(): array
    {
        $excluded = array_merge(
            ['id', 'created_at', 'updated_at', 'password', 'remember_token'],
            $this->auditExclude ?? []
        );

        $changes = [];
        foreach ($this->getChanges() as $key => $new) {
            if (in_array($key, $excluded, true)) {
                continue;
            }
            $changes[$key] = ['old' => $this->getOriginal($key), 'new' => $new];
        }

        return $changes;
    }

    protected function auditLabel(): string
    {
        return $this->name ?? $this->name_en ?? $this->title ?? '#'.$this->getKey();
    }

    protected function auditDescription(string $event): string
    {
        $noun = Str::headline(class_basename(static::class));

        return sprintf('%s "%s" %s', $noun, $this->auditLabel(), $event);
    }
}
