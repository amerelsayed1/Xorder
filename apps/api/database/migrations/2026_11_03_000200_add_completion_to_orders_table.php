<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * When an order was completed, and by whom — the completion twin of the
 * cancellation columns added earlier the same day.
 *
 * Powers the Orders page's "handled by" and "time to complete" and the CSV
 * export. Stamped by the server wherever an order becomes COMPLETED: a staff
 * click, a closed or expired table visit, or a till order paid in full.
 * Cleared if a completion is corrected to CANCELLED.
 *
 * Nullable and additive: orders completed before this read null, and the
 * screens show a dash rather than a guess.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            if (! Schema::hasColumn('orders', 'completed_at')) {
                $table->timestamp('completed_at')->nullable();
            }
            if (! Schema::hasColumn('orders', 'completed_by')) {
                $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            }
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            if (Schema::hasColumn('orders', 'completed_by')) {
                $table->dropConstrainedForeignId('completed_by');
            }
            if (Schema::hasColumn('orders', 'completed_at')) {
                $table->dropColumn('completed_at');
            }
        });
    }
};
