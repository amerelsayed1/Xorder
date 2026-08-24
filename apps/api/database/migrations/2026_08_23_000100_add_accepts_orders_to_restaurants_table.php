<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A tenant-controlled switch for "are we taking orders right now".
     *
     * This is NOT the entitlement. The plan features (whatsapp_ordering /
     * system_ordering) decide whether a restaurant may take orders at all, and
     * only the Super Admin changes those. This answers the operational question
     * the owner needs on a busy Friday — kitchen is swamped, stop the queue —
     * without anyone touching their subscription.
     *
     * An earlier `ordering_enabled` column was dropped as redundant with the
     * entitlements; this is deliberately a different question, owned by a
     * different person, so it comes back under a name that says so.
     */
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->boolean('accepts_orders')->default(true)->after('ordering_mode');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('accepts_orders');
        });
    }
};
