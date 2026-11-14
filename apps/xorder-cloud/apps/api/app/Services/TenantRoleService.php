<?php

namespace App\Services;

use App\Enums\TenantCapability as Cap;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;

/**
 * Creation/mutation of a restaurant's custom staff roles.
 *
 * `capabilities` is guarded (non-fillable) on {@see Role}: it is the privilege
 * boundary, so it is only ever set here — after being expanded (manage implies
 * view) and intersected with what the acting user is themselves allowed to
 * grant. That intersection is what stops a manager with `staff.manage` from
 * minting a role more powerful than their own.
 */
class TenantRoleService
{
    /**
     * The one role every restaurant is seeded with: Admin, holding every
     * capability, marked `is_system` so it can never be deleted.
     *
     * A tenant always needs at least one assignable role, and it must be one
     * they cannot remove from under themselves — so exactly one is protected,
     * and it is the unrestricted one. Narrower roles (waiter, kitchen, …) are
     * left to the owner to create if they want them: they are opinions about
     * how a particular restaurant is staffed, not facts about the product, and
     * shipping four undeletable guesses cluttered the screen for everyone.
     *
     * @return array<string, array{name:string, name_ar:string, capabilities:list<Cap>}>
     */
    public static function presets(): array
    {
        return [
            'admin' => [
                'name' => 'Admin',
                'name_ar' => 'مدير النظام',
                // Everything, including staff.manage — this role is the
                // tenant-side equivalent of the owner's own access.
                'capabilities' => Cap::cases(),
            ],
        ];
    }

    /**
     * Seed the protected Admin role for a freshly provisioned restaurant.
     * Called inside the provisioning transaction, so a restaurant is never left
     * without a role to assign.
     */
    public function seedSystemRoles(Restaurant $restaurant): void
    {
        foreach (self::presets() as $slug => $preset) {
            $role = $restaurant->roles()->make([
                'name' => $preset['name'],
                'name_ar' => $preset['name_ar'],
            ]);

            $role->forceFill([
                'restaurant_id' => $restaurant->id,
                'slug' => $slug,
                'is_system' => true,
                'capabilities' => Cap::expand(array_map(fn (Cap $c) => $c->value, $preset['capabilities'])),
            ])->save();
        }
    }

    /**
     * @param  array{name:string, name_ar?:?string, capabilities:list<string>}  $data
     */
    public function create(User $actor, array $data): Role
    {
        $role = new Role([
            'name' => $data['name'],
            'name_ar' => $data['name_ar'] ?? null,
        ]);

        // restaurant_id is stamped by BelongsToRestaurant from the actor's
        // tenant context — never from request input.
        $role->forceFill([
            'capabilities' => $this->grantable($actor, $data['capabilities'] ?? []),
            'is_system' => false,
        ])->save();

        return $role;
    }

    /**
     * @param  array{name:string, name_ar?:?string, capabilities:list<string>}  $data
     */
    public function update(User $actor, Role $role, array $data): Role
    {
        $role->fill([
            'name' => $data['name'],
            'name_ar' => $data['name_ar'] ?? null,
        ]);

        $role->forceFill([
            'capabilities' => $this->grantable($actor, $data['capabilities'] ?? []),
        ])->save();

        return $role;
    }

    /**
     * The capabilities an actor may actually put on a role: the requested set,
     * expanded so every `*.manage` carries its `*.view`, then intersected with
     * what the actor holds. The owner holds everything, so for them this is a
     * no-op; for a delegated manager it is the "cannot grant above self" rule.
     *
     * @param  list<string>  $requested
     * @return list<string>
     */
    public function grantable(User $actor, array $requested): array
    {
        $expanded = Cap::expand($requested);

        return array_values(array_filter(
            $expanded,
            fn (string $value) => $actor->holdsTenantCapability($value),
        ));
    }

    /**
     * Which of the requested capabilities the actor may NOT grant — used to fail
     * loudly at validation time instead of silently dropping them.
     *
     * @param  list<string>  $requested
     * @return list<string>
     */
    public function ungrantable(User $actor, array $requested): array
    {
        $expanded = Cap::expand($requested);

        return array_values(array_filter(
            $expanded,
            fn (string $value) => ! $actor->holdsTenantCapability($value),
        ));
    }
}
