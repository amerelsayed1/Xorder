<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Per-restaurant custom roles. Each restaurant builds its own set (seeded with
 * four system presets at provisioning time) and assigns one to each staff
 * account via users.role_id.
 *
 * users.role stays the coarse portal discriminator (RESTAURANT_ADMIN owner vs
 * RESTAURANT_STAFF employee vs the platform roles); users.role_id carries the
 * fine-grained capability set and is only ever set for RESTAURANT_STAFF.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('roles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 80);
            $table->string('name_ar', 80)->nullable();
            // list<string> of TenantCapability values.
            $table->json('capabilities');
            // System presets seeded per restaurant: renamable and editable, but
            // never deletable, so a tenant can't strand itself with no roles.
            $table->boolean('is_system')->default(false);
            // Stable handle for the seeded presets ('manager', 'cashier', …);
            // null for roles the restaurant created itself.
            $table->string('slug', 40)->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'name']);
            $table->index(['restaurant_id', 'is_system']);
        });

        Schema::table('users', function (Blueprint $table) {
            // restrictOnDelete, not nullOnDelete: a staff account with a null
            // role_id would have no capabilities at all, and silently blanking
            // access on role deletion hides the mistake. RoleController forces
            // an explicit reassignment instead.
            $table->foreignId('role_id')->nullable()->after('role')
                ->constrained('roles')->restrictOnDelete();
        });

        $this->restoreSqlitePerTenantUsernameIndex();
        $this->backfillSystemRoles();
    }

    /**
     * Every restaurant that already exists gets the one role a newly provisioned
     * one is seeded with — Admin, holding every capability — so no live tenant
     * opens the Roles page to an empty table and no owner is blocked from adding
     * their first staff member.
     *
     * Only Admin, deliberately. Narrower presets (manager, cashier, waiter,
     * kitchen) are opinions about how a particular restaurant is staffed, not
     * facts about the product; shipping four undeletable guesses cluttered the
     * screen for everyone. An owner creates the ones they actually want.
     *
     * The capability list is written out literally rather than read from
     * TenantCapability: a migration is a frozen snapshot of one moment, and it
     * must keep producing the same rows however the enum evolves. These are the
     * post-split verb values, so the later split migration finds nothing to
     * translate here.
     */
    private function backfillSystemRoles(): void
    {
        // Frozen snapshot of TenantCapability at the time of this migration.
        $capabilities = [
            'live.view',
            'orders.view', 'orders.update',
            'menu.view', 'menu.create', 'menu.update', 'menu.delete',
            'tables.view', 'tables.create', 'tables.update', 'tables.delete',
            'branches.view', 'branches.create', 'branches.update', 'branches.delete',
            'bills.view', 'bills.update',
            'customers.view',
            'reviews.view', 'reviews.update',
            'analytics.view',
            'reports.view',
            'settings.view', 'settings.update',
            'staff.view', 'staff.create', 'staff.update', 'staff.delete',
        ];

        $now = now();
        $rows = [];

        foreach (DB::table('restaurants')->pluck('id') as $restaurantId) {
            $rows[] = [
                'restaurant_id' => $restaurantId,
                'name' => 'Admin',
                'name_ar' => 'مدير النظام',
                'capabilities' => json_encode($capabilities),
                'is_system' => true,
                'slug' => 'admin',
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }

        foreach (array_chunk($rows, 200) as $chunk) {
            DB::table('roles')->insert($chunk);
        }
    }

    /**
     * SQLite cannot attach a foreign key in place: it rebuilds the whole table
     * and re-creates every index from pragma metadata. Expression indexes do not
     * survive that round trip — users_username_per_tenant_unique (UNIQUE over
     * COALESCE(restaurant_id, 0), username, added by
     * 2026_07_21_000300_make_username_unique_per_tenant) comes back as a plain
     * UNIQUE on username, which would stop two restaurants from each having a
     * "manager". Rebuild it by hand.
     *
     * Postgres (production) alters the table in place and needs none of this.
     */
    private function restoreSqlitePerTenantUsernameIndex(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            return;
        }

        DB::statement('DROP INDEX IF EXISTS users_username_per_tenant_unique');
        DB::statement('CREATE UNIQUE INDEX users_username_per_tenant_unique ON users (COALESCE(restaurant_id, 0), username)');
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('role_id');
        });

        // The same rebuild happens on the way back down.
        $this->restoreSqlitePerTenantUsernameIndex();

        Schema::dropIfExists('roles');
    }
};
