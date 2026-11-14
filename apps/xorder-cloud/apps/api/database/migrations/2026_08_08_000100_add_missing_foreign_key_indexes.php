<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Index foreign-key columns that had none.
 *
 * `foreignId()->constrained()` creates the FK constraint but NOT an index on
 * the referencing column. MySQL auto-indexes FKs; PostgreSQL (production) does
 * not. Every column below is either joined on, filtered on, or scanned during a
 * parent delete (nullOnDelete/cascadeOnDelete) — without an index those are
 * sequential scans of the child table. All additive; no data change.
 *
 * FK columns already covered by the leading column of an existing composite
 * index (e.g. options.option_group_id, dining_areas.branch_id) are intentionally
 * skipped to avoid redundant indexes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->index('customer_id');
            $table->index('branch_id');
            $table->index('dining_area_id');
            $table->index('table_id');
            $table->index('menu_session_id');
        });

        Schema::table('bill_requests', function (Blueprint $table) {
            $table->index('order_id');
            $table->index('menu_session_id');
            $table->index('branch_id');
        });

        Schema::table('internal_reviews', function (Blueprint $table) {
            $table->index('order_id');
            $table->index('bill_request_id');
            $table->index('menu_session_id');
            $table->index('branch_id');
        });

        Schema::table('menu_sessions', function (Blueprint $table) {
            $table->index('branch_id');
            $table->index('dining_area_id');
        });

        Schema::table('customer_addresses', function (Blueprint $table) {
            $table->index('customer_id');
        });

        Schema::table('device_tokens', function (Blueprint $table) {
            $table->index('user_id');
        });

        Schema::table('combo_group_items', function (Blueprint $table) {
            $table->index('menu_item_id');
        });

        Schema::table('review_internal_notes', function (Blueprint $table) {
            $table->index('internal_review_id');
        });

        Schema::table('menu_item_option_group', function (Blueprint $table) {
            $table->index('option_group_id');
        });

        Schema::table('option_group_category', function (Blueprint $table) {
            $table->index('category_id');
        });

        // Scanned daily by ProcessSubscriptionsCommand
        // (WHERE subscription_status IN (...) AND subscription_end_date <op> date).
        Schema::table('restaurants', function (Blueprint $table) {
            $table->index(['subscription_status', 'subscription_end_date']);
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['customer_id']);
            $table->dropIndex(['branch_id']);
            $table->dropIndex(['dining_area_id']);
            $table->dropIndex(['table_id']);
            $table->dropIndex(['menu_session_id']);
        });

        Schema::table('bill_requests', function (Blueprint $table) {
            $table->dropIndex(['order_id']);
            $table->dropIndex(['menu_session_id']);
            $table->dropIndex(['branch_id']);
        });

        Schema::table('internal_reviews', function (Blueprint $table) {
            $table->dropIndex(['order_id']);
            $table->dropIndex(['bill_request_id']);
            $table->dropIndex(['menu_session_id']);
            $table->dropIndex(['branch_id']);
        });

        Schema::table('menu_sessions', function (Blueprint $table) {
            $table->dropIndex(['branch_id']);
            $table->dropIndex(['dining_area_id']);
        });

        Schema::table('customer_addresses', function (Blueprint $table) {
            $table->dropIndex(['customer_id']);
        });

        Schema::table('device_tokens', function (Blueprint $table) {
            $table->dropIndex(['user_id']);
        });

        Schema::table('combo_group_items', function (Blueprint $table) {
            $table->dropIndex(['menu_item_id']);
        });

        Schema::table('review_internal_notes', function (Blueprint $table) {
            $table->dropIndex(['internal_review_id']);
        });

        Schema::table('menu_item_option_group', function (Blueprint $table) {
            $table->dropIndex(['option_group_id']);
        });

        Schema::table('option_group_category', function (Blueprint $table) {
            $table->dropIndex(['category_id']);
        });

        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropIndex(['subscription_status', 'subscription_end_date']);
        });
    }
};
