<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The public IP(s) this branch's customer Wi-Fi exits through.
     *
     * Learned, never configured: the owner is not asked to find their public IP
     * (most could not, and it rotates). BranchEgressIpService derives it from
     * sessions the geofence already proved were on-premises. Deliberately not
     * fillable on the model, so no dashboard request can inject a value that
     * would make presence look verified.
     */
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->json('egress_ips')->nullable();
            $table->timestamp('egress_ips_learned_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn(['egress_ips', 'egress_ips_learned_at']);
        });
    }
};
