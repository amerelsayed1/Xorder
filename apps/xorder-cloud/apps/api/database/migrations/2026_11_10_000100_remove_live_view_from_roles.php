<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

return new class extends Migration
{
    private const LIVE_VIEW = 'live.view';

    /**
     * live-board-to-pos D9/D11: the dashboard's Live board is gone, so the
     * `live.view` capability is removed from every role that held it. Nothing
     * replaces it (D11): `orders.read` and `bills.read` used to accept it and
     * now need `orders.view` / `bills.view`.
     *
     * A role that held `live.view` but neither of those loses its order and
     * bill reads. They are logged (restaurant, role, name) as the list the
     * owner asked to see; nothing is granted in their place.
     *
     * Data only, no schema change: the column is JSON text and the rows are
     * rewritten in place, one by one.
     */
    public function up(): void
    {
        foreach (DB::table('roles')->select('id', 'restaurant_id', 'name', 'capabilities')->cursor() as $role) {
            $caps = json_decode($role->capabilities ?? '[]', true);

            if (! is_array($caps) || ! in_array(self::LIVE_VIEW, $caps, true)) {
                continue;
            }

            if (! in_array('orders.view', $caps, true) && ! in_array('bills.view', $caps, true)) {
                Log::warning('live.view removed: role loses its order access', [
                    'restaurant_id' => $role->restaurant_id,
                    'role_id' => $role->id,
                    'role' => $role->name,
                ]);
            }

            DB::table('roles')->where('id', $role->id)->update([
                'capabilities' => json_encode(array_values(array_diff($caps, [self::LIVE_VIEW]))),
            ]);
        }
    }

    /**
     * Not reversible: which roles held `live.view` is not recorded anywhere
     * once it is removed. The capability no longer exists in the enum either.
     */
    public function down(): void
    {
        //
    }
};
