<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice b (D3): what a business buys and counts. A table of its
     * own, NOT a MenuItem flag: menu_items.category_id is NOT NULL, and
     * PlanLimitService counts every MenuItem against max_items, so buying
     * chicken must not eat the menu quota. A product that is sold AND
     * counted (bottled water) links to its menu item.
     *
     * Additive: a brand-new table, nothing existing changes.
     *
     * - unique(menu_item_id): NULLs are distinct on SQLite and PostgreSQL,
     *   so any number of stock-only items can exist, while a menu item is
     *   counted once.
     * - `unit_code` stores the unit's immutable code (units.code), never an
     *   id. It can't change while the item holds stock in any branch or sits
     *   on an open purchase order (StockItemService, under a lock): a receipt
     *   never converts units.
     * - No delete. Retired with is_active = false: movements point at it.
     */
    public function up(): void
    {
        Schema::create('stock_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_item_id')->nullable()->constrained('menu_items')->nullOnDelete();
            // Either name may be absent, but not both (FormRequest).
            $table->string('name_en', 160)->nullable();
            $table->string('name_ar', 160)->nullable();
            $table->string('sku', 64)->nullable();
            $table->string('unit_code', 16);
            $table->boolean('is_active')->default(true);
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique('menu_item_id');
            $table->index(['restaurant_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_items');
    }
};
