<?php

use App\Enums\TenantCapability;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * The live board used to be gated on `tables.view`; it now has its own
     * `live.view`. Without this, every role that could open the board this
     * morning would lose it on deploy — a silent removal of access nobody
     * asked for.
     *
     * Granted to roles holding tables.view specifically, because that is
     * precisely who could reach the board before the split. Roles with only
     * orders.view could not, and do not gain it here.
     */
    public function up(): void
    {
        foreach (DB::table('roles')->select('id', 'capabilities')->cursor() as $role) {
            $caps = json_decode($role->capabilities ?? '[]', true);

            if (! is_array($caps) || ! in_array(TenantCapability::TABLES_VIEW->value, $caps, true)) {
                continue;
            }

            if (in_array('live.view', $caps, true)) {
                continue;
            }

            DB::table('roles')->where('id', $role->id)->update([
                // expand() re-sorts into enum order, keeping stored JSON stable.
                'capabilities' => json_encode(TenantCapability::expand([...$caps, 'live.view'])),
            ]);
        }
    }

    public function down(): void
    {
        foreach (DB::table('roles')->select('id', 'capabilities')->cursor() as $role) {
            $caps = json_decode($role->capabilities ?? '[]', true);

            if (! is_array($caps)) {
                continue;
            }

            DB::table('roles')->where('id', $role->id)->update([
                'capabilities' => json_encode(array_values(array_diff($caps, ['live.view']))),
            ]);
        }
    }
};
