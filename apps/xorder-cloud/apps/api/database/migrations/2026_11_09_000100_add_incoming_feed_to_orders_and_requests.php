<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The till's incoming feed (POS-BE-033, pos-incoming-cloud-orders S3/S4).
 *
 * Purely additive: nullable columns and one defaulted boolean, no backfill, no
 * rewrite of existing rows. "Accepted" is not an order status — an accepted
 * online order is a NEW order with `accepted_at` set, so OrderStatus (and every
 * reader of it) is untouched. A rejected one is CANCELLED with `rejected_at`
 * and the reason the diner sees.
 *
 * PostgreSQL (by reading; tests run on SQLite): ADD COLUMN with NULL or a
 * constant default is metadata-only. But the whole file runs in one transaction,
 * so the ACCESS EXCLUSIVE lock on `orders` is held through the non-NOT-VALID FK
 * validation (a full scan of orders / bill_requests) and the non-concurrent
 * index builds, which block writes. Deploy at low traffic; if `orders` is above
 * roughly 1M rows, split the indexes into their own migration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->boolean('online_orders_on_pos')->default(false);
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->timestamp('accepted_at')->nullable();
            $table->foreignId('accepted_by_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->string('accept_client_request_id', 64)->nullable();
            $table->timestamp('rejected_at')->nullable();
            $table->string('reject_reason', 255)->nullable();
            $table->string('reject_client_request_id', 64)->nullable();
            $table->index(['restaurant_id', 'branch_id', 'updated_at', 'id'], 'orders_feed_idx');
        });

        Schema::table('bill_requests', function (Blueprint $table) {
            $table->foreignId('handled_by_terminal_id')->nullable()->constrained('pos_terminals')->nullOnDelete();
            $table->string('handled_client_request_id', 64)->nullable();
            $table->index(['restaurant_id', 'branch_id', 'updated_at', 'id'], 'bill_requests_feed_idx');
        });

        Schema::table('pos_terminals', function (Blueprint $table) {
            $table->timestamp('last_feed_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('pos_terminals', function (Blueprint $table) {
            $table->dropColumn('last_feed_at');
        });

        Schema::table('bill_requests', function (Blueprint $table) {
            $table->dropIndex('bill_requests_feed_idx');
            $table->dropConstrainedForeignId('handled_by_terminal_id');
            $table->dropColumn('handled_client_request_id');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex('orders_feed_idx');
            $table->dropConstrainedForeignId('accepted_by_terminal_id');
            $table->dropColumn([
                'accepted_at', 'accept_client_request_id',
                'rejected_at', 'reject_reason', 'reject_client_request_id',
            ]);
        });

        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn('online_orders_on_pos');
        });
    }
};
