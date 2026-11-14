<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-009 — shifts and cash movements. Cash-up is the reason a
     * restaurant buys a POS.
     *
     * opened_at / closed_at / occurred_at are CLIENT-supplied and stored as
     * sent — a shift opened at 08:00 offline and synced at 23:45 must not
     * record 23:45. received_at is the server's own observation.
     *
     * One open shift per terminal is enforced in the service under a lock on
     * the terminal row (SHIFT_ALREADY_OPEN). Money is integer minor units
     * throughout (D1).
     */
    public function up(): void
    {
        Schema::create('pos_shifts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_terminal_id')->constrained('pos_terminals')->cascadeOnDelete();
            $table->uuid('client_transaction_id');
            $table->foreignId('opened_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('closed_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('opened_at');
            $table->timestamp('closed_at')->nullable();
            $table->timestamp('received_at')->nullable();
            $table->unsignedBigInteger('opening_float_minor')->default(0);
            $table->unsignedBigInteger('counted_cash_minor')->nullable();
            $table->unsignedBigInteger('expected_cash_minor')->nullable();
            $table->bigInteger('variance_minor')->nullable(); // signed: short is negative
            $table->string('variance_reason')->nullable();
            $table->json('denominations')->nullable();
            $table->string('status', 10)->default('open'); // open | closed
            $table->char('payload_hash', 64)->nullable();
            $table->char('close_payload_hash', 64)->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'client_transaction_id']);
            $table->index(['restaurant_id', 'pos_terminal_id', 'status']);
        });

        Schema::create('pos_cash_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_shift_id')->constrained('pos_shifts')->cascadeOnDelete();
            $table->foreignId('pos_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->uuid('client_transaction_id');
            $table->foreignId('acting_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('direction', 3); // in | out
            $table->unsignedBigInteger('amount_minor');
            $table->string('reason', 120);
            $table->string('reference')->nullable();
            $table->timestamp('occurred_at');
            $table->timestamp('received_at')->nullable();
            $table->char('payload_hash', 64)->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'client_transaction_id']);
        });

        // pos_shift_id FKs added after pos_shifts exists (orders + payments
        // reference shifts; shifts reference terminals; no cycle).
        Schema::table('orders', function (Blueprint $table) {
            $table->foreign('pos_shift_id')->references('id')->on('pos_shifts')->nullOnDelete();
        });
        Schema::table('order_payments', function (Blueprint $table) {
            $table->foreign('pos_shift_id')->references('id')->on('pos_shifts')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('order_payments', function (Blueprint $table) {
            $table->dropForeign(['pos_shift_id']);
        });
        Schema::table('orders', function (Blueprint $table) {
            $table->dropForeign(['pos_shift_id']);
        });
        Schema::dropIfExists('pos_cash_movements');
        Schema::dropIfExists('pos_shifts');
    }
};
