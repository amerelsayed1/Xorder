<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-010 groundwork, and the one thing that was blocking refunds
     * entirely: **a line the till can name.**
     *
     * An offline till builds a refund against its OWN `pos_order_lines.id`. It
     * has never seen `order_items.id` — the order it is refunding may still be
     * in the outbox — so `xorder-pos/lib/data/cloud/outbox_drain.dart` refuses
     * to enqueue a refund at all ("a refund needs the platform's order-item
     * ids, not this database's local line ids"). `client_line_id` is the cure:
     * the till stamps each order line with a key of its own choosing, the
     * platform stores it verbatim, and a refund addresses lines by
     * (order client_transaction_id, client_line_id) — two facts the till knows
     * before it has ever spoken to the server.
     *
     * unique(order_id, client_line_id) rather than an index: a duplicate key
     * inside one order would make the refund address ambiguous, and the right
     * place to refuse that is the database, once. NULL is not unique in either
     * SQLite or PostgreSQL, so every existing row (all NULL) and every QR order
     * (which never sends one) is unaffected.
     *
     * `refunded_quantity` / `refunded_minor` are COUNTERS, not derivable
     * conveniences. They are what the NEXT refund checks, inside the same
     * transaction, under the same row lock — recomputing the figure from
     * pos_refund_lines is how a line gets refunded twice at two tills (the
     * till's own reasoning, xorder-pos migration 12).
     */
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->string('client_line_id', 64)->nullable();
            $table->unsignedInteger('refunded_quantity')->default(0);

            $table->unique(['order_id', 'client_line_id']);
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->unsignedBigInteger('refunded_minor')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('refunded_minor');
        });

        Schema::table('order_items', function (Blueprint $table) {
            $table->dropUnique(['order_id', 'client_line_id']);
            $table->dropColumn(['client_line_id', 'refunded_quantity']);
        });
    }
};
