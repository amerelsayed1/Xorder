<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-008 — the per-branch invoice counter. Incremented under
     * lockForUpdate() INSIDE the order-creation transaction; a MAX()+1 scan
     * double-issues under two concurrent tills and is the forbidden design.
     *
     * `period` is the reset bucket: '2026' (yearly), '2026-09' (monthly) or
     * 'all' (never). A replayed client_transaction_id never touches this table
     * — the number is stored on the order and replays read it back.
     */
    public function up(): void
    {
        Schema::create('invoice_sequences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->string('period', 10);
            $table->unsignedBigInteger('next_value')->default(1);
            $table->timestamps();

            $table->unique(['restaurant_id', 'branch_id', 'period']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('invoice_sequences');
    }
};
