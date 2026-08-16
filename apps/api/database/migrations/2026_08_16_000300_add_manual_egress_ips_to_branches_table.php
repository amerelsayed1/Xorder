<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Owner-declared customer Wi-Fi addresses, kept separate from the learned
     * ones (`egress_ips`).
     *
     * Two columns rather than one because the two have different lifecycles and
     * must not overwrite each other: the nightly learning job rewrites its own
     * list from scratch every run, so anything an owner typed would be erased
     * the same night. Matching takes the union of both.
     *
     * This is the setup path for a branch with no history yet — waiting for
     * five organic geofence-verified scans is a poor first-run experience when
     * the owner is standing in the venue on the very connection we need.
     */
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->json('egress_ips_manual')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn('egress_ips_manual');
        });
    }
};
