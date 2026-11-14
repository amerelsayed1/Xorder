<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * BE-A01 — payments as first-class rows. Split tender is the NORMAL case at
     * a till ("300 cash + 200 card" is two rows, not columns on orders).
     *
     * Decision (a): each row carries its OWN client_transaction_id, distinct
     * from the order envelope's, because settling an open bill later — possibly
     * from another terminal — is a real flow that needs its own dedupe key.
     * Unique per tenant, same as orders.
     *
     * amount_minor is unsigned: a refund is never a negative payment — refund
     * tenders live on the refund record (POS-BE-010, deferred).
     */
    public function up(): void
    {
        Schema::create('order_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_shift_id')->nullable();
            $table->foreignId('pos_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->foreignId('acting_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->uuid('client_transaction_id');
            $table->foreignId('tender_type_id')->nullable()->constrained('tender_types')->nullOnDelete();
            $table->unsignedBigInteger('amount_minor');
            $table->string('currency', 3);
            $table->timestamp('received_at')->nullable();        // client's event time, as sent
            $table->timestamp('received_server_at')->nullable(); // when the server first saw it
            $table->char('payload_hash', 64)->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'client_transaction_id']);
            $table->index(['restaurant_id', 'order_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_payments');
    }
};
