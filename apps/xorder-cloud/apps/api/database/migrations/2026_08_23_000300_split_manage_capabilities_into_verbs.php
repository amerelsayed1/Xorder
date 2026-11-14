<?php

use App\Enums\TenantCapability;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Roles stored a blanket `<resource>.manage`; permissions are now per-verb
     * (create / update / delete), so every saved role has to be rewritten or it
     * would grant nothing at all — the old strings no longer match any gate.
     *
     * The translation is deliberately loss-free in the permissive direction:
     * `menu.manage` becomes create+update+delete, which is exactly what it
     * allowed before. Nobody gains or loses access on deploy; they simply gain
     * the ability to be given less next time.
     */
    public function up(): void
    {
        foreach (DB::table('roles')->select('id', 'capabilities')->cursor() as $role) {
            $stored = json_decode($role->capabilities ?? '[]', true);

            if (! is_array($stored) || $stored === []) {
                continue;
            }

            $translated = TenantCapability::expand($stored);

            if ($translated !== $stored) {
                DB::table('roles')->where('id', $role->id)->update([
                    'capabilities' => json_encode($translated),
                ]);
            }
        }
    }

    /**
     * Irreversible by design: create+update+delete collapses back to `manage`
     * cleanly, but a role granted only `menu.create` has no pre-split
     * equivalent — rolling it back would have to either widen it to manage or
     * drop it, and both are wrong. The forward migration is idempotent, so a
     * re-run after a revert is safe.
     */
    public function down(): void {}
};
