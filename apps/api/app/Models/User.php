<?php

namespace App\Models;

use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Models\Concerns\Auditable;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use Auditable, HasApiTokens, HasFactory, Notifiable;

    // Never surface credential columns in audit change diffs.
    protected array $auditExclude = ['password', 'remember_token', 'email_verified_at'];

    // `role`, `role_id` and `restaurant_id` are deliberately NOT mass-assignable:
    // they are the privilege/tenant boundary and must only ever be set explicitly
    // in trusted provisioning code, never from request input. This prevents a
    // future `User::create($request->all())`/`update()` from letting a caller
    // self-promote to SUPER_ADMIN, grant themselves capabilities, or hop tenants.
    protected $fillable = [
        'name',
        'username',
        'email',
        'password',
        'status',
    ];

    /** Usernames are case-insensitive: always stored lowercase + trimmed. */
    protected function username(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $value === null ? null : mb_strtolower(trim($value)),
        );
    }

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'password_changed_at' => 'datetime',
            'role' => RoleEnum::class,
            'status' => UserStatus::class,
        ];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /**
     * The custom in-restaurant role backing this account's capabilities. Named
     * `tenantRole` rather than `role` because `role` is already the coarse
     * RoleEnum attribute. Only ever set for RESTAURANT_STAFF.
     */
    public function tenantRole(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }

    public function isSuperAdmin(): bool
    {
        return $this->role === RoleEnum::SUPER_ADMIN;
    }

    public function isRestaurantAdmin(): bool
    {
        return $this->role === RoleEnum::RESTAURANT_ADMIN;
    }

    public function isRestaurantStaff(): bool
    {
        return $this->role === RoleEnum::RESTAURANT_STAFF;
    }

    /** Any account that belongs to a restaurant (owner or staff). */
    public function isTenantUser(): bool
    {
        return $this->role->isTenantRole();
    }

    public function isActive(): bool
    {
        return $this->status === UserStatus::ACTIVE;
    }

    /**
     * Does this account hold a fine-grained in-restaurant capability?
     *
     * The restaurant owner (RESTAURANT_ADMIN) implicitly holds all of them —
     * the tenant-side mirror of the SUPER_ADMIN Gate::before bypass. Staff hold
     * exactly what their assigned Role lists; a staff account with no role has
     * no capabilities at all (fail closed). Platform roles hold none: they are
     * blocked from the dashboard by the route's `role:` gate long before this.
     */
    public function holdsTenantCapability(TenantCapability|string $capability): bool
    {
        if ($this->role === RoleEnum::RESTAURANT_ADMIN) {
            return true;
        }

        if ($this->role !== RoleEnum::RESTAURANT_STAFF) {
            return false;
        }

        return $this->tenantRole?->grants($capability) ?? false;
    }

    /**
     * Every in-restaurant capability this account holds, for the client to
     * mirror in the UI. Empty for platform users.
     *
     * @return list<string>
     */
    public function tenantCapabilities(): array
    {
        if ($this->role === RoleEnum::RESTAURANT_ADMIN) {
            return self::withLegacyAliases(TenantCapability::values());
        }

        if ($this->role !== RoleEnum::RESTAURANT_STAFF) {
            return [];
        }

        return self::withLegacyAliases($this->tenantRole?->capabilityValues() ?? []);
    }

    /**
     * Append the pre-split `<resource>.manage` values a role's verbs add up to.
     *
     * Purely a deploy-window courtesy. A dashboard tab opened before the release
     * runs JavaScript that gates its sidebar on `settings.manage`, `staff.manage`
     * and friends; once those vanish from this list, that tab hides Settings,
     * Staff and Roles from everyone — owners included — until the user happens
     * to hard-reload. Publishing the old names alongside the new ones keeps
     * those tabs working through the changeover.
     *
     * Nothing server-side consults these: every gate is on a verb. The role
     * editor builds its grid from the TenantCapability catalogue, not from here,
     * so no stale checkboxes appear either.
     *
     * REMOVE ONE RELEASE AFTER THE VERB SPLIT SHIPS — by then no browser is
     * still holding the old bundle, and this is dead weight in every /auth/me.
     *
     * @param  list<string>  $verbs
     * @return list<string>
     */
    private static function withLegacyAliases(array $verbs): array
    {
        $held = array_flip($verbs);

        foreach (TenantCapability::legacyManageMap() as $legacy => $impliedVerbs) {
            // The alias is only honest if the role holds everything it stood for.
            foreach ($impliedVerbs as $verb) {
                if (! isset($held[$verb])) {
                    continue 2;
                }
            }

            $verbs[] = $legacy;
        }

        return $verbs;
    }
}
