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

        User::updateOrCreate(
            ['email' => $email],
            [
                'name' => config('platform.super_admin.name'),
                'password' => Hash::make(config('platform.super_admin.password')),
                'role' => RoleEnum::SUPER_ADMIN,
                'restaurant_id' => null,
                'status' => UserStatus::ACTIVE,
                'email_verified_at' => now(),
            ],
        );

        $this->command?->info("Super Admin ready: {$email}");
    }
}
