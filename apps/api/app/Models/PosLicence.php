<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A POS licence: an Ed25519-signed entitlement document issued to one client.
 *
 * Deliberately has NO RestaurantScope. Licences are administered from the
 * platform side, across tenants, by Super Admin — the same posture the fleet
 * views in POS-BE-022 need. Tenant-facing reads resolve the restaurant from the
 * authenticated terminal, never from request input.
 *
 * ## Two kinds of client
 *
 * A `cloud` licence names a `restaurants` row: the customer is a tenant we
 * host, and the licence is minted with them (RestaurantProvisioningService).
 *
 * An `offline` licence names NOBODY on this platform. `restaurant_id` is null
 * and the customer lives in this row's own columns. That is not a shortcut —
 * it is the point: an on-premises customer whose sales never leave their
 * building must not appear as a tenant, because a tenant is where products,
 * orders, branches and money would then hang. What we keep is the licence
 * management minimum — who owns it, what they bought, when it lapses, is it
 * revoked. Everything else stays in the restaurant.
 *
 * @property-read ?Restaurant $restaurant
 */
class PosLicence extends Model
{
    /**
     * Descriptive columns only.
     *
     * restaurant_id, kind, customer_name, customer_slug, licence_ref, key_hash,
     * key_last_four, payload, signature and key_id are NOT fillable: they are
     * set exclusively by LicenceIssuer via forceFill, following the discipline
     * that already protects users.role and users.restaurant_id. Mass assignment
     * must never be able to re-point a licence at another client or swap its
     * signed artifact — and on an offline licence the customer columns ARE the
     * client, feeding the `tenant_slug` and `tenant_name` claims directly.
     */
    protected $fillable = [
        'plan_id',
        // Commercial contact for an offline customer. Descriptive, so fillable
        // — unlike the identity columns below them, which decide what gets
        // SIGNED and are therefore forceFilled by LicenceIssuer alone.
        'contact_name',
        'contact_email',
        'contact_phone',
        'lifetime',
        'issued_at',
        'expires_at',
        'grace_days',
        'warn_days',
        'max_terminals',
        'max_users',
        'max_offline_days',
        'features',
        'modes',
        'branch_ids',
        'fingerprints',
        'notes',
    ];

    /**
     * The signed artifact and the key hash are never serialised. The payload is
     * exposed only through the deliberate file endpoints, never as a side
     * effect of returning a model.
     */
    protected $hidden = [
        'key_hash',
        'payload',
        'signature',
    ];

    protected function casts(): array
    {
        return [
            'issued_at' => 'datetime',
            'expires_at' => 'datetime',
            'revoked_at' => 'datetime',
            'activated_at' => 'datetime',
            'features' => 'array',
            'modes' => 'array',
            'branch_ids' => 'array',
            'fingerprints' => 'array',
            'lifetime' => 'boolean',
        ];
    }

    /** A licence for a tenant we host. */
    public const KIND_CLOUD = 'cloud';

    /** A licence for a customer who is not on this platform at all. */
    public const KIND_OFFLINE = 'offline';

    /**
     * The term stored for a licence sold outright.
     *
     * A sentinel rather than a null `expires_at`, because `expires_at` is a
     * REQUIRED claim in every till already in the field — LicenseClaims.fromJson
     * reads it unconditionally, and those binaries verify offline and cannot be
     * updated from here. A null would not parse; a date in 2099 parses
     * everywhere and simply never arrives. The `lifetime` flag is what the
     * dashboard reads so an operator sees "Lifetime", not that date.
     */
    public const LIFETIME_EXPIRES_AT = '2099-12-31 00:00:00';

    /** No tenant on this platform — the customer lives in this row. */
    public function isOffline(): bool
    {
        return $this->kind === self::KIND_OFFLINE;
    }

    /**
     * Who this licence was sold to, however they are recorded.
     *
     * The one place that decides between the tenant and the row's own columns,
     * so the claims, the audit trail and the dashboard cannot disagree about a
     * customer's name.
     */
    public function clientName(): string
    {
        if ($this->isOffline()) {
            return $this->customer_name ?: $this->customer_slug ?: $this->licence_ref;
        }

        $restaurant = $this->restaurant;

        return $restaurant?->name_en ?: $restaurant?->name_ar ?: ($restaurant?->slug ?? $this->licence_ref);
    }

    /** The identifier a till configures itself with — the `tenant_slug` claim. */
    public function clientSlug(): string
    {
        return $this->isOffline()
            ? (string) $this->customer_slug
            : (string) $this->restaurant?->slug;
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function supersededBy(): BelongsTo
    {
        return $this->belongsTo(self::class, 'superseded_by_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_id');
    }

    /**
     * Rows a terminal may still activate: not revoked, not replaced by a newer
     * one. A renewal reuses the activation key, so a single key can match
     * several rows and only the live one may be handed out.
     */
    public function scopeLive(Builder $query): Builder
    {
        return $query->whereNull('revoked_at')->whereNull('superseded_by_id');
    }

    /** When trade actually stops: expiry plus the grace window. */
    public function graceEndsAt(): Carbon
    {
        return $this->expires_at->copy()->addDays($this->grace_days);
    }

    /**
     * Operator-facing state, for the Super Admin list.
     *
     * This mirrors — but does not replace — the client's own evaluation. The
     * till decides what it may do from the signed claims alone, offline; this
     * is the platform's view of the same facts, and the two can legitimately
     * disagree while a till is out of contact.
     */
    public function state(?Carbon $now = null): string
    {
        $now ??= Carbon::now();

        return match (true) {
            $this->revoked_at !== null => 'revoked',
            $this->superseded_by_id !== null => 'superseded',
            $now->lt($this->issued_at) => 'pending',
            // Sold outright. Stated before the date arithmetic rather than
            // relying on the 2099 sentinel to lose every comparison, so the
            // sentinel stays an implementation detail of storage.
            $this->lifetime => 'active',
            $now->gt($this->graceEndsAt()) => 'expired',
            $now->gt($this->expires_at) => 'in_grace',
            $now->gte($this->expires_at->copy()->subDays($this->warn_days)) => 'expiring_soon',
            default => 'active',
        };
    }

    /** Days until expiry; negative once past it. */
    public function daysRemaining(?Carbon $now = null): int
    {
        return (int) ($now ?? Carbon::now())->startOfDay()
            ->diffInDays($this->expires_at->copy()->startOfDay(), false);
    }

    /** The distributable file: exactly the three keys LicenseFile.tryParse reads. */
    public function file(): array
    {
        return [
            'payload' => $this->payload,
            'signature' => $this->signature,
            'key_id' => $this->key_id,
        ];
    }
}
