<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            // A variant group is a size/portion selector: single-select, and the
            // chosen option's price REPLACES the item base price instead of
            // adding to it (small/medium/large, 12/18/24 pieces, …).
            $table->boolean('is_variant')->default(false)->after('is_required');
        });
    }

    public function down(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->dropColumn('is_variant');
        });
    }
};
