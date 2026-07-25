<?php

namespace Database\Seeders;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // The single platform Super Admin. Credentials come from config/.env so
        // they are never hard-coded. Idempotent: safe to re-run.
        $email = config('platform.super_admin.email');
        $password = (string) config('platform.super_admin.password');

        // Fail closed: never provision the platform admin with an empty/default
        // credential. A blank SUPER_ADMIN_PASSWORD must abort seeding rather
        // than silently create a super-admin whose password is guessable.
        if (trim($password) === '') {
            throw new \RuntimeException(
                'SUPER_ADMIN_PASSWORD is not set. Refusing to seed the platform Super Admin with an empty/default password.'
            );
        }

        $admin = User::firstOrNew(['email' => $email]);
        // forceFill: role/restaurant_id are guarded and only set in trusted code.
        $admin->forceFill([
            'name' => config('platform.super_admin.name'),
            'username' => config('platform.super_admin.username'),
            'password' => Hash::make($password),
            'role' => RoleEnum::SUPER_ADMIN,
            'restaurant_id' => null,
            'status' => UserStatus::ACTIVE,
            'email_verified_at' => now(),
        ])->save();

        $this->command?->info("Super Admin ready: {$email}");

        // Subscription plans catalog (managed at /plans).
        $this->call(PlanSeeder::class);
    }
}
