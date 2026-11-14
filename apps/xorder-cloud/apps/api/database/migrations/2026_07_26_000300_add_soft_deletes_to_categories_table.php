<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Add soft-delete support to categories. The name-uniqueness constraints
     * are swapped for partial indexes scoped to live rows (deleted_at IS NULL)
     * so a category name freed by a soft-delete can be reused. Both Postgres
     * (production) and SQLite (dev/test) support partial unique indexes.
     */
    public function up(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->softDeletes();
            $table->dropUnique(['restaurant_id', 'name_en']);
            $table->dropUnique(['restaurant_id', 'name_ar']);
        });

        DB::statement('CREATE UNIQUE INDEX categories_restaurant_id_name_en_active_unique ON categories (restaurant_id, name_en) WHERE deleted_at IS NULL');
        DB::statement('CREATE UNIQUE INDEX categories_restaurant_id_name_ar_active_unique ON categories (restaurant_id, name_ar) WHERE deleted_at IS NULL');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX categories_restaurant_id_name_en_active_unique');
        DB::statement('DROP INDEX categories_restaurant_id_name_ar_active_unique');

        Schema::table('categories', function (Blueprint $table) {
            $table->unique(['restaurant_id', 'name_en']);
            $table->unique(['restaurant_id', 'name_ar']);
            $table->dropSoftDeletes();
        });
    }
};
