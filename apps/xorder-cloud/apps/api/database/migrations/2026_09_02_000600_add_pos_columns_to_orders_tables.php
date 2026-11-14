<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-006/007/008 — POS columns on the EXISTING order graph. One order
     * history, distinguished by `channel`; a parallel "POS order" table is the
     * forbidden design.
     *
     * All columns nullable/defaulted so every existing row and every future
     * public-path row is untouched. Money lands twice on purpose (D1):
     * integer minor units are authoritative for POS; orders.total keeps its
     * decimal(10,2) projection so the dashboard, stats and reports are blind
     * to the change.
     *
     * client_transaction_id unique per TENANT, not globally — two tenants may
     * legitimately mint the same UUID. payload_hash is the canonical hash of
     * the money-bearing request fields: a replayed key with a different hash is
     * a client bug (422 IDEMPOTENCY_PAYLOAD_MISMATCH), never a silent create.
     *
     * received_at vs created_at: created_at holds the CLIENT's event time,
     * stored as sent (an offline order is genuinely hours old); received_at is
     * when the server first saw it. Nothing overwrites a client timestamp
     * (POS-BE-020).
     */
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->string('channel', 12)->default('qr');
            $table->uuid('client_transaction_id')->nullable();
            $table->string('invoice_number', 40)->nullable()->index();
            $table->unsignedBigInteger('subtotal_minor')->nullable();
            $table->unsignedBigInteger('discount_minor')->nullable();
            $table->unsignedBigInteger('tax_minor')->nullable();
            $table->unsignedBigInteger('charges_minor')->nullable();
            $table->unsignedBigInteger('total_minor')->nullable();
            $table->foreignId('pos_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->foreignId('pos_shift_id')->nullable();
            $table->foreignId('acting_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('received_at')->nullable();
            $table->char('payload_hash', 64)->nullable();
            $table->json('pos_meta')->nullable();

            $table->unique(['restaurant_id', 'client_transaction_id']);
        });

        Schema::table('order_items', function (Blueprint $table) {
            $table->unsignedBigInteger('unit_price_minor')->nullable();
            $table->unsignedBigInteger('line_total_minor')->nullable();
            $table->string('price_source', 20)->nullable(); // server | client_asserted
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn(['unit_price_minor', 'line_total_minor', 'price_source']);
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique(['restaurant_id', 'client_transaction_id']);
            $table->dropConstrainedForeignId('pos_terminal_id');
            $table->dropConstrainedForeignId('acting_user_id');
            $table->dropColumn([
                'channel', 'client_transaction_id', 'invoice_number',
                'subtotal_minor', 'discount_minor', 'tax_minor', 'charges_minor',
                'total_minor', 'pos_shift_id', 'received_at', 'payload_hash', 'pos_meta',
            ]);
        });
    }
};
