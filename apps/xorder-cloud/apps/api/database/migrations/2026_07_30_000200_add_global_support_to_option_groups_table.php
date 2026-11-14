<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Turn option groups into a reusable ("global") library.
 *
 * A global group belongs to the restaurant, not to a single item, so
 * `menu_item_id` becomes nullable. Inline per-item groups keep their
 * `menu_item_id`; global groups leave it null and set `is_global = true`.
 * Items reference global groups through the menu_item_option_group pivot.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->boolean('is_global')->default(false)->after('menu_item_id')->index();
        });

        // Drop the FK before altering the column, then re-add it — this keeps the
        // change portable across SQLite (dev/CI) and PostgreSQL (prod).
        Schema::table('option_groups', function (Blueprint $table) {
            $table->dropForeign(['menu_item_id']);
        });

        Schema::table('option_groups', function (Blueprint $table) {
            $table->foreignId('menu_item_id')->nullable()->change();
        });

        Schema::table('option_groups', function (Blueprint $table) {
            $table->foreign('menu_item_id')->references('id')->on('menu_items')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->dropForeign(['menu_item_id']);
        });

        Schema::table('option_groups', function (Blueprint $table) {
            $table->foreignId('menu_item_id')->nullable(false)->change();
        });

        Schema::table('option_groups', function (Blueprint $table) {
            $table->foreign('menu_item_id')->references('id')->on('menu_items')->cascadeOnDelete();
            $table->dropIndex(['is_global']);
            $table->dropColumn('is_global');
        });
    }
};
