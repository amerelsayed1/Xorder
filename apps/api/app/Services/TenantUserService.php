<?php

namespace App\Services;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\Role;
use App\Models\User;
use App\Notifications\StaffCredentials;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Trusted creation/mutation of restaurant staff accounts — the tenant mirror of
 * {@see PlatformUserService}.
 *
 * Everything privileged is set through forceCreate/forceFill: `role` is pinned
 * to RESTAURANT_STAFF (this service can never mint an owner or a platform user),
 * `restaurant_id` comes from the acting user's tenant, never from input, and
 * `role_id` is only accepted after the caller has been shown to hold every
 * capability that role grants.
 */
class TenantUserService
{
    /**
     * Create a staff account inside the actor's restaurant. When no password is
     * supplied a strong one is generated and returned (and emailed, if the
     * account has an address) so the manager can hand it over.
     *
     * @param  array{name:string, username:string, email?:?string, status?:string, password?:?string, role_id:int}  $data
     * @return array{user: User, generated_password: ?string}
     */
    public function create(User $actor, array $data): array
    {
        $generatedPassword = null;
        $plainPassword = $data['password'] ?? null;

        if (empty($plainPassword)) {
            $generatedPassword = $this->generatePassword();
            $plainPassword = $generatedPassword;
        }

        $user = User::forceCreate([
            'name' => $data['name'],
            'username' => $data['username'],
            'email' => $data['email'] ?? null,
            'password' => Hash::make($plainPassword),
            'password_changed_at' => now(),
            'role' => RoleEnum::RESTAURANT_STAFF,
            'role_id' => (int) $data['role_id'],
            // The tenant comes from who is asking, never from the payload.
            'restaurant_id' => $actor->restaurant_id,
            'status' => UserStatus::from($data['status'] ?? UserStatus::ACTIVE->value),
            'email_verified_at' => now(),
        ]);

        $this->notifyCredentials($user, $plainPassword);

        return [
            'user' => $user->load('tenantRole'),
            'generated_password' => $generatedPassword,
        ];
    }

    /**
     * Update a staff account's identity, assigned role and status. Password is
     * handled separately by resetPassword().
     *
     * @param  array{name:string, username:string, email?:?string, status?:string, role_id:int}  $data
     */
    public function update(User $user, array $data): User
    {
        $user->forceFill([
            'name' => $data['name'],
            'username' => $data['username'],
            'email' => $data['email'] ?? null,
            'role_id' => (int) $data['role_id'],
            'status' => UserStatus::from($data['status'] ?? $user->status->value),
        ])->save();

        return $user->load('tenantRole');
    }

    /**
     * Regenerate a staff password and return the new plaintext once. Stamping
     * password_changed_at rejects every JWT minted before the reset — the
     * offboarding primitive for a staff member who walked out with a phone.
     */
    public function resetPassword(User $user): string
    {
        $password = $this->generatePassword();

        $user->forceFill([
            'password' => $password, // hashed by the 'hashed' cast
            'password_changed_at' => now(),
        ])->save();

        $this->notifyCredentials($user, $password);

        return $password;
    }

    /**
     * Move every user holding $role onto $replacement — the reassign step that
     * makes deleting a role safe (users.role_id is restrictOnDelete, and a null
     * role_id would leave an account with no capabilities at all).
     */
    public function reassignRole(Role $role, Role $replacement): int
    {
        return User::query()
            ->where('restaurant_id', $role->restaurant_id)
            ->where('role_id', $role->id)
            ->update(['role_id' => $replacement->id]);
    }

    private function notifyCredentials(User $user, string $password): void
    {
        if (! $user->email || ! $user->restaurant) {
            return;
        }

        $user->notify(new StaffCredentials($user->restaurant, $password));
    }

    private function generatePassword(): string
    {
        return Str::password(16, symbols: false);
    }
}
