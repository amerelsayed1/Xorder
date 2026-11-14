<?php

namespace App\Models;

use App\Enums\TenantCapability;
use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A custom staff role inside one restaurant. `capabilities` is a list of
 * {@see TenantCapability} values; the Gate resolves a RESTAURANT_STAFF user's
 * abilities from the role assigned to them (users.role_id).
 *
 * `is_system` marks the Admin role seeded at provisioning time — it may be
 * renamed and re-scoped, but not deleted.
 */
class Role extends Model
{
    use Auditable, BelongsToRestaurant;

    // `capabilities` is deliberately NOT mass-assignable: it is the privilege
    // boundary. TenantRoleService sets it explicitly, after expanding and
    // intersecting it against what the acting user is allowed to grant.
    protected $fillable = [
        'name',
        'name_ar',
    ];

    protected function casts(): array
    {
        return [
            'capabilities' => 'array',
            'is_system' => 'boolean',
        ];
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    /** @return list<string> */
    public function capabilityValues(): array
    {
        return array_values(array_filter(
            (array) ($this->capabilities ?? []),
            fn ($value) => TenantCapability::tryFrom((string) $value) !== null,
        ));
    }

    public function grants(TenantCapability|string $capability): bool
    {
        $value = $capability instanceof TenantCapability ? $capability->value : $capability;

        return in_array($value, $this->capabilityValues(), true);
    }
}
