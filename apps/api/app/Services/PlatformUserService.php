<?php

namespace App\Services;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\User;
use App\Notifications\PlatformUserCredentials;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Trusted creation/mutation of platform staff users (restaurant_id = null).
 * `role` and `restaurant_id` are guarded (non-fillable) on {@see User}, so they
 * are set here via forceCreate/forceFill only — never mass-assigned from input.
 */
class PlatformUserService
{
    /**
     * Create a platform user. When no password is supplied, a strong one is
     * generated and returned (and emailed) so the Super Admin can hand it over.
     *
     * @param  array{name:string, username:string, email:string, role:string, status?:string, password?:?string}  $data
     * @return array{user: User, generated_password: ?string}
     */
    public function create(array $data): array
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
            'email' => $data['email'],
            'password' => Hash::make($plainPassword),
            'password_changed_at' => now(),
            'role' => RoleEnum::from($data['role']),
            'restaurant_id' => null,
            'status' => UserStatus::from($data['status'] ?? UserStatus::ACTIVE->value),
            'email_verified_at' => now(),
        ]);

        $user->notify(new PlatformUserCredentials($plainPassword));

        return [
            'user' => $user,
            'generated_password' => $generatedPassword,
        ];
    }

    /**
     * Update a platform user's identity/role/status. Password is handled
     * separately by resetPassword().
     *
     * @param  array{name:string, username:string, email:string, role:string, status?:string}  $data
     */
    public function update(User $user, array $data): User
    {
        // role/status are guarded/cast; forceFill so role can be reassigned by
        // trusted code without opening it to mass assignment elsewhere.
        $user->forceFill([
            'name' => $data['name'],
            'username' => $data['username'],
            'email' => $data['email'],
            'role' => RoleEnum::from($data['role']),
            'status' => UserStatus::from($data['status'] ?? $user->status->value),
        ])->save();

        return $user;
    }

    /**
     * Regenerate a platform user's password, re-email it, and return the new
     * plaintext once. Stamps password_changed_at so tokens minted before the
     * reset are rejected by the JWT guard.
     */
    public function resetPassword(User $user): string
    {
        $password = $this->generatePassword();

        $user->forceFill([
            'password' => $password,
            'password_changed_at' => now(),
        ])->save();

        $user->notify(new PlatformUserCredentials($password));

        return $password;
    }

    private function generatePassword(): string
    {
        return Str::password(16, symbols: false);
    }
}
