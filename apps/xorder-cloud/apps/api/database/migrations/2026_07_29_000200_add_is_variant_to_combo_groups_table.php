<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('combo_groups', function (Blueprint $table) {
            // A variant group is a size/portion selector: single-select, and the
            // chosen item's price REPLACES the combo base price instead of adding
            // to it (small/medium/large meal, …).
            $table->boolean('is_variant')->default(false)->after('max_select');
        });
    }

    public function down(): void
    {
        Schema::table('combo_groups', function (Blueprint $table) {
            $table->dropColumn('is_variant');
        });
    }
};
