<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Guest paging (docs/features/guest-paging): the diner's phone replaces
     * the counter pager. A SEPARATE pickup lifecycle beside `status` — the
     * platform's OrderStatus enum does not grow (BACKEND_TO_POS §010, final).
     *
     * Every column is nullable with no default, so existing rows and the
     * QR/POS write paths are untouched (catalog-only ADD COLUMN on PostgreSQL).
     * `pickup_token` is unique over an all-null column today — NULLs never
     * collide on either engine — and the index is load-bearing: the public
     * URL carries no slug, so GuestPagingService::generateToken() checks the
     * token across every tenant. Deliberately NO index on pickup_status: the
     * board filters it with `!=` inside an OR, which no btree can use; the
     * existing (restaurant_id, created_at) index already serves that query.
     *
     * PostgreSQL (reviewed by reading; SQLite tests cannot prove it): the
     * whole migration runs in one transaction, so `orders` is under ACCESS
     * EXCLUSIVE from the first ADD COLUMN to COMMIT — two scans of the table
     * (unique index build, FK validation over all-null rows). Fine at our
     * sizes; it queues behind any in-flight order transaction, as every
     * orders migration here does.
     *
     * `restaurants.guest_paging_order_types` null means the default set
     * (GuestPagingService::DEFAULT_ORDER_TYPES); the owner may widen it.
     */
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->string('pickup_token', 40)->nullable()->unique();
            $table->string('pickup_status', 12)->nullable();
            // What the slip or the success screen showed the diner. POS sales
            // send it (receipt_number); QR orders use ORD-<id>.
            $table->string('pickup_display_ref', 40)->nullable();
            $table->timestamp('pickup_followed_at')->nullable();
            $table->timestamp('ready_at')->nullable();
            $table->foreignId('ready_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('ready_source', 10)->nullable(); // pos | dashboard
            $table->timestamp('acknowledged_at')->nullable();
            $table->timestamp('picked_up_at')->nullable();
            $table->string('pickup_push_token', 512)->nullable();
        });

        Schema::table('restaurants', function (Blueprint $table) {
            $table->json('guest_paging_order_types')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('guest_paging_order_types');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('ready_by');
            $table->dropUnique(['pickup_token']);
            $table->dropColumn([
                'pickup_token', 'pickup_status', 'pickup_display_ref', 'pickup_followed_at',
                'ready_at', 'ready_source', 'acknowledged_at', 'picked_up_at', 'pickup_push_token',
            ]);
        });
    }
};
