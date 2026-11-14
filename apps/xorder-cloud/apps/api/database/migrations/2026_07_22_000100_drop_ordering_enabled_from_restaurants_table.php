<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Ordering availability is decided by the plan entitlements
     * (whatsapp_ordering / system_ordering → Restaurant::effectiveOrderingMode),
     * so the standalone per-restaurant switch is redundant and removed. To
     * disable ordering for a client, drop its ordering feature(s) or move it to
     * a plan without an ordering channel.
     */
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('ordering_enabled');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->boolean('ordering_enabled')->default(true)->after('currency');
        });
    }
};
