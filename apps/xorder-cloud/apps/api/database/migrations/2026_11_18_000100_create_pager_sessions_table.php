<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr). Additive
 * only: one new table, nothing existing is touched.
 *
 * A pairing session is what a phone gets when it scans the restaurant's one
 * standing QR: a short `code` the client reads out to the cashier, and a long
 * secret it keeps (only its hash is stored). When the cashier enters the code
 * with an order, the session is bound to that order and the code is freed.
 *
 *  - unique (restaurant_id, code): an open code is unique within one
 *    restaurant. NULLs do not collide in PostgreSQL or SQLite, so binding sets
 *    the code to NULL and the number is free for the next client at once.
 *  - unique order_id: an order is paired at most once.
 *  - nullOnDelete: deleting an order never deletes the session row; the
 *    prune job removes old rows.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pager_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 8)->nullable();
            $table->string('secret_hash', 64)->unique();
            $table->foreignId('order_id')->nullable()->unique()->constrained()->nullOnDelete();
            $table->timestamp('expires_at');
            $table->timestamp('bound_at')->nullable();
            $table->timestamps();

            $table->unique(['restaurant_id', 'code']);
            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pager_sessions');
    }
};
