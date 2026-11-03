<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Why, when and by whom an order was cancelled.
 *
 * Until now a cancelled order said only CANCELLED. The reason is optional free
 * text typed by staff; when and who are stamped by the server. All three are
 * cleared again if staff correct a cancellation to COMPLETED, so they always
 * describe the order's current state, never a past one.
 *
 * Nullable and additive: every order cancelled before this reads null, and
 * the till never sends or reads these columns.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            if (! Schema::hasColumn('orders', 'cancellation_reason')) {
                $table->string('cancellation_reason', 255)->nullable();
            }
            if (! Schema::hasColumn('orders', 'cancelled_at')) {
                $table->timestamp('cancelled_at')->nullable();
            }
            if (! Schema::hasColumn('orders', 'cancelled_by')) {
                $table->foreignId('cancelled_by')->nullable()->constrained('users')->nullOnDelete();
            }
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            if (Schema::hasColumn('orders', 'cancelled_by')) {
                $table->dropConstrainedForeignId('cancelled_by');
            }
            foreach (['cancelled_at', 'cancellation_reason'] as $column) {
                if (Schema::hasColumn('orders', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
