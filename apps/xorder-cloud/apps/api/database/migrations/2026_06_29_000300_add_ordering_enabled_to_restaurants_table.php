<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // When false, the public menu is view-only: no add-to-cart / cart /
            // WhatsApp ordering. Super Admin controls this per restaurant.
            $table->boolean('ordering_enabled')->default(true)->after('currency');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('ordering_enabled');
        });
    }
};
