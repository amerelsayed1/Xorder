<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // When false, the public menu is shown in the default language only
            // (no EN/AR switcher). Super Admin controls this per restaurant.
            $table->boolean('bilingual')->default(true)->after('default_language');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('bilingual');
        });
    }
};
