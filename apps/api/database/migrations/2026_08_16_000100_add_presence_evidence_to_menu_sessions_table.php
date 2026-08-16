<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Keeps the evidence that admitted a table session instead of discarding it
     * once the fence check passes.
     *
     * Two reasons. First, presence disputes ("this order wasn't from my table")
     * currently have nothing to review. Second, the branch's customer Wi-Fi
     * egress IP can be learned from sessions the geofence already vouched for —
     * see BranchEgressIpService — which needs the source address recorded next
     * to the proof that the diner really was on the premises.
     */
    public function up(): void
    {
        Schema::table('menu_sessions', function (Blueprint $table) {
            // Public source address of the scan. 45 chars covers IPv6 including
            // the IPv4-mapped form.
            $table->string('client_ip', 45)->nullable();

            // The fix the fence was tested against (null when no fence applies).
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->unsignedSmallInteger('accuracy_m')->nullable();

            // How presence was established: 'geofence' when the fence check ran
            // and passed, null when the branch has no fence to check against.
            // Only sessions with a source here are trusted to teach egress IPs.
            $table->string('presence_source', 20)->nullable();

            // Did client_ip match a learned egress IP for this branch?
            // Null means the branch has learned none yet, so the question could
            // not be answered — distinct from a definite false.
            $table->boolean('on_branch_network')->nullable();

            $table->index(
                ['branch_id', 'presence_source', 'started_at'],
                'menu_sessions_egress_learning_idx'
            );
        });
    }

    public function down(): void
    {
        Schema::table('menu_sessions', function (Blueprint $table) {
            $table->dropIndex('menu_sessions_egress_learning_idx');
            $table->dropColumn([
                'client_ip',
                'latitude',
                'longitude',
                'accuracy_m',
                'presence_source',
                'on_branch_network',
            ]);
        });
    }
};
