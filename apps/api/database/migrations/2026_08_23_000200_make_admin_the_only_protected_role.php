<?php

use App\Models\Restaurant;
use App\Services\TenantRoleService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Restaurants provisioned before this point carry four protected presets
     * (Manager / Cashier / Waiter / Kitchen). The product now seeds exactly one
     * undeletable role — Admin — and leaves narrower roles to the owner.
     *
     * This deliberately does NOT delete the old presets: staff accounts are
     * assigned to them, and dropping a role out from under a working schedule
     * would either orphan those accounts or silently widen their access. It
     * unprotects them instead, so an owner can remove the ones they don't use
     * on their own terms, and adds the Admin role where it is missing.
     */
    public function up(): void
    {
        $seeder = app(TenantRoleService::class);

        Restaurant::query()->withoutGlobalScopes()->cursor()->each(function (Restaurant $restaurant) use ($seeder) {
            $hasAdmin = DB::table('roles')
                ->where('restaurant_id', $restaurant->id)
                ->where('slug', 'admin')
                ->exists();

            if (! $hasAdmin) {
                $seeder->seedSystemRoles($restaurant);
            }

            // Everything else keeps working; it is merely deletable now.
            DB::table('roles')
                ->where('restaurant_id', $restaurant->id)
                ->where('slug', '!=', 'admin')
                ->update(['is_system' => false]);
        });
    }

    /**
     * Re-protecting the old presets would be guesswork (some may have been
     * renamed or deleted by then), so this only steps back the Admin role's
     * protection — the roles themselves are left exactly as they are.
     */
    public function down(): void
    {
        DB::table('roles')->where('slug', 'admin')->update(['is_system' => false]);
    }
};
