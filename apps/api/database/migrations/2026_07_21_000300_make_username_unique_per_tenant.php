<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Usernames are unique PER TENANT, not globally: two restaurants may
        // each have a "manager". COALESCE folds super-admins (restaurant_id
        // NULL) into a single "tenant 0" namespace so they can't collide
        // either (a plain composite unique would treat NULLs as distinct).
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['username']);
        });

        DB::statement('CREATE UNIQUE INDEX users_username_per_tenant_unique ON users (COALESCE(restaurant_id, 0), username)');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX users_username_per_tenant_unique');

        Schema::table('users', function (Blueprint $table) {
            $table->unique('username');
        });
    }
};
