<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice c, D11 (decided by the owner 2026-09-13: "finish all
     * phases"): closing a part delivery short.
     *
     * Additive: four NULLABLE columns on purchase_orders, nothing else. Every
     * existing row reads as "not closed short", which is the truth.
     *
     * Why no new status value: the till's PurchaseStatus has five values and
     * its fromWire() THROWS on an unknown one, and its own documentation of
     * `received` is "all of it arrived, or somebody closed the difference
     * deliberately" (purchase_order.dart). Its migration 44 already allows
     * partially_received → received with lines still short, for exactly this.
     * So a short-closed order is `received`, plus these columns saying who
     * closed it, when and why. What was not coming is each line's outstanding
     * quantity at that moment, and it can never change afterwards: a received
     * order takes no more receipts.
     *
     * Nothing here touches the stock ledger. Closing short writes no movement.
     */
    public function up(): void
    {
        Schema::table('purchase_orders', function (Blueprint $table) {
            $table->timestamp('closed_short_at')->nullable();
            $table->foreignId('closed_short_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('close_reason', 32)->nullable();
            $table->text('close_note')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('purchase_orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('closed_short_by');
            $table->dropColumn(['closed_short_at', 'close_reason', 'close_note']);
        });
    }
};
