<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which licence a till last checked against, and when (R2, POS-BE-031).
 *
 * Telemetry written by POST /api/pos/license/check the way the heartbeat
 * writes its own: saveQuietly, never audited. It is what the Super Admin
 * per-terminal view reads to say "this till last confirmed its licence on …".
 * Nullable — a till that never checked has nothing to say.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('pos_terminals', function (Blueprint $table) {
            if (! Schema::hasColumn('pos_terminals', 'licence_id')) {
                $table->foreignId('licence_id')->nullable()->constrained('pos_licences')->nullOnDelete();
            }
            if (! Schema::hasColumn('pos_terminals', 'last_licence_check_at')) {
                $table->timestamp('last_licence_check_at')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('pos_terminals', function (Blueprint $table) {
            $table->dropConstrainedForeignId('licence_id');
            $table->dropColumn('last_licence_check_at');
        });
    }
};
