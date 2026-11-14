<?php

namespace App\Http\Requests\Dashboard\Concerns;

use App\Enums\TenantCapability;
use App\Models\Role;
use App\Services\TenantRoleService;
use Illuminate\Contracts\Validation\Validator;

/**
 * "Cannot grant above self" — the escalation guard for tenant-side staff
 * management. A delegated manager holding `staff.manage` must not be able to
 * build a role, or assign an existing one, carrying capabilities they do not
 * themselves hold; otherwise `staff.manage` silently becomes every capability.
 *
 * The restaurant owner holds everything, so this is a no-op for them.
 */
trait GrantsTenantCapabilities
{
    /** @return list<string> */
    protected function requestedCapabilities(): array
    {
        return array_map('strval', (array) $this->input('capabilities', []));
    }

    /** @return list<string> */
    protected function capabilityValues(): array
    {
        return TenantCapability::values();
    }

    /**
     * Fail validation naming the capabilities the actor may not hand out —
     * loudly, rather than silently dropping them from the saved role.
     *
     * @param  list<string>  $requested
     */
    protected function rejectUngrantable(Validator $validator, array $requested, string $field = 'capabilities'): void
    {
        $actor = $this->user();

        if ($actor === null) {
            return;
        }

        $denied = app(TenantRoleService::class)->ungrantable($actor, $requested);

        if ($denied === []) {
            return;
        }

        $validator->errors()->add($field, __('xorder.messages.role_capability_above_self', [
            'capabilities' => implode(', ', array_map(
                fn (string $c) => __('xorder.capabilities.'.str_replace('.', '_', $c)),
                $denied,
            )),
        ]));
    }

    /**
     * The same rule applied to `role_id`: you may only put someone into a role
     * whose whole capability set you already hold.
     */
    protected function rejectRoleAboveSelf(Validator $validator): void
    {
        $roleId = (int) $this->input('role_id');

        if ($roleId <= 0) {
            return;
        }

        // RestaurantScope constrains this to the actor's own tenant; a role from
        // another restaurant simply isn't found (the `exists` rule reports it).
        $role = Role::find($roleId);

        if ($role === null) {
            return;
        }

        $this->rejectUngrantable($validator, $role->capabilityValues(), 'role_id');
    }
}
