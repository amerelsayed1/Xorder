<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Refuse a table session unless the scan arrives from the branch's own
     * customer Wi-Fi.
     *
     * Off by default, and deliberately per-branch rather than platform-wide:
     * the egress-IP signal is corroboration, not proof (see
     * BranchEgressIpService), so switching it on turns a soft signal into a
     * hard gate and will refuse every diner on mobile data. A branch opts in
     * with its eyes open, one at a time, and can watch its own on-Wi-Fi rate
     * before doing so.
     */
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->boolean('require_branch_wifi')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn('require_branch_wifi');
        });
    }
};
