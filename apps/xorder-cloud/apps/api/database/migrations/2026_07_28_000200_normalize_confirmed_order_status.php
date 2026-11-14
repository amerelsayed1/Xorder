<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Defensive one-time normalization for the CONFIRMED order-status removal.
        //
        // CONFIRMED was dropped from the OrderStatus enum because nothing ever set
        // it (orders are created NEW and only move to COMPLETED/CANCELLED). But
        // `orders.status` is a plain string column, so any lingering 'CONFIRMED'
        // row from older code would make the enum cast throw the moment it loads.
        // Rewrite any such rows to a valid status so the enum removal is
        // crash-proof. Expected to affect zero rows on every current environment;
        // this exists purely as a safety net. Uses the query builder (not Eloquent)
        // so it never triggers the cast, and stays portable across sqlite/postgres.
        DB::table('orders')
            ->where('status', 'CONFIRMED')
            ->update(['status' => 'COMPLETED']);
    }

    public function down(): void
    {
        // No-op: CONFIRMED no longer exists in the enum and the original rows
        // cannot be reconstructed.
    }
};
