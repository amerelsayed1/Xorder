<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // How the public menu presents items: 'photo' (image cards, default),
            // 'text-grid' (image-less cards) or 'text-list' (classic printed list).
            $table->string('menu_layout', 20)->default('photo')->after('secondary_color');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('menu_layout');
        });
    }
};
