<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Bilingual snapshot on the order line (R1).
 *
 * An order line stored a single `name`, so a POS order showed only the
 * language captured at sale time — wrong when the dashboard is switched to the
 * other locale. Menu items are bilingual (`name_ar`/`name_en`); the line was
 * not. These two columns let the backend FREEZE both languages from the
 * resolved `menu_item_id` at creation, so history stays accurate even if the
 * item is later renamed or deleted, and the dashboard resolves by locale.
 *
 * Additive and nullable: every existing row keeps its `name`, and the display
 * path falls back to `name` when these are null (historical + QR/public rows).
 * Guarded with hasColumn — this production DB has carried out-of-CI migration
 * state before.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            if (! Schema::hasColumn('order_items', 'name_ar')) {
                $table->string('name_ar')->nullable()->after('name');
            }
            if (! Schema::hasColumn('order_items', 'name_en')) {
                $table->string('name_en')->nullable()->after('name_ar');
            }
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn(['name_ar', 'name_en']);
        });
    }
};
