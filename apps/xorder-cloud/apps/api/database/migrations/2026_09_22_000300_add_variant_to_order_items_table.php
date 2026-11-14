<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The size/portion a diner picked (a variant option group) used to travel as
 * just another label inside `options`, so the kitchen could not tell
 * "Medium" from "extra cheese". Give it its own column. Additive and nullable:
 * rows written before this migration keep the variant inside `options`, which
 * the dashboard still renders.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->string('variant', 200)->nullable()->after('quantity');
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn('variant');
        });
    }
};
