<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-010 — a refund is a **reversing counter-record**. The original
     * order is never mutated, never deleted, and its `status` never moves: the
     * OrderStatus invariant (NEW → COMPLETED|CANCELLED) is untouched, exactly
     * as agreed under A4. What a refund changes is the DERIVED
     * `settlement_status` and the two counters the previous migration added.
     *
     * Three tables, mirroring the till's own shape (`pos_refunds`,
     * `pos_refund_lines`, `pos_refund_payments`):
     *
     *   pos_refunds         the document — one credit note
     *   pos_refund_lines    what went back, per original order line
     *   pos_refund_tenders  how the money went back
     *
     * There are deliberately **no negative `order_payments` rows**: that column
     * is unsigned and a refund is not a payment with a minus sign (the 2026-09-02
     * order_payments migration says so out loud). Refund tenders live here.
     *
     * `credit_note_number` is drawn from the same `invoice_sequences` mechanism
     * as an invoice number, in its own `CN-` period bucket, under the same row
     * lock inside the same transaction. A replayed client_transaction_id reads
     * the stored number back and consumes nothing.
     */
    public function up(): void
    {
        Schema::create('pos_refunds', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            // RESTRICT on the order: deleting a sale must never orphan the
            // record of money given back against it.
            $table->foreignId('order_id')->constrained()->restrictOnDelete();
            $table->foreignId('pos_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->foreignId('pos_shift_id')->nullable()->constrained('pos_shifts')->nullOnDelete();
            $table->foreignId('acting_user_id')->nullable()->constrained('users')->nullOnDelete();
            // Who authorised it above the till's own ceiling. The supervisor
            // gate itself is a client-side concern (§010); the server records
            // the name it was given.
            $table->foreignId('authorized_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->uuid('client_transaction_id');
            $table->string('credit_note_number', 40)->nullable()->index();
            $table->string('kind', 8)->default('refund'); // refund | void
            $table->string('reason')->nullable();
            $table->unsignedBigInteger('total_minor');
            $table->string('currency', 3);
            $table->timestamp('occurred_at');          // client's event time, as sent
            $table->timestamp('received_at')->nullable();
            $table->char('payload_hash', 64)->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'client_transaction_id']);
            $table->index(['restaurant_id', 'order_id']);
            $table->index(['restaurant_id', 'pos_shift_id']);
        });

        Schema::create('pos_refund_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_refund_id')->constrained('pos_refunds')->cascadeOnDelete();
            $table->foreignId('order_item_id')->constrained('order_items')->restrictOnDelete();
            $table->unsignedInteger('quantity');
            $table->unsignedBigInteger('unit_price_minor');
            $table->unsignedBigInteger('amount_minor');
            // The name as it was sold, again: an item renamed in March must not
            // rewrite what a credit note said in January.
            $table->string('name_snapshot')->nullable();
            $table->timestamps();

            // One row per original line per refund. Two rows would still total
            // correctly and would make the credit note unreadable.
            $table->unique(['pos_refund_id', 'order_item_id']);
        });

        Schema::create('pos_refund_tenders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_refund_id')->constrained('pos_refunds')->cascadeOnDelete();
            $table->foreignId('tender_type_id')->nullable()->constrained('tender_types')->nullOnDelete();
            $table->unsignedBigInteger('amount_minor');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_refund_tenders');
        Schema::dropIfExists('pos_refund_lines');
        Schema::dropIfExists('pos_refunds');
    }
};
