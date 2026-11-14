<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * T0.2 — the prerequisite for server-side pricing (POS-BE-006).
     *
     * order_items has only ever carried a `name` string, which is why re-pricing
     * was structurally impossible and why ReportService matches products by name
     * (BE-A05). Nullable: every existing row, and every future row from the
     * public WhatsApp path, has no id to record. No behaviour change anywhere —
     * the public order path does not set it.
     *
     * nullOnDelete, not cascade: deleting a menu item must never delete sales
     * history. (menu_items soft-deletes, so the FK action almost never fires,
     * but a force-delete must degrade the line to its name snapshot, not erase
     * the sale.)
     */
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->foreignId('menu_item_id')->nullable()->after('order_round_id')
                ->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropConstrainedForeignId('menu_item_id');
        });
    }
};
