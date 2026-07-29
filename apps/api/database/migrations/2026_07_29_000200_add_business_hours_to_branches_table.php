<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            // Structured per-weekday hours keyed by day (sat..fri) →
            // { closed, always, open, close }. Mirrors the restaurant-level
            // business_hours; the built-in "always" flag on every day is the
            // "open 24 hours" state, so no separate 24/7 column is needed.
            $table->json('business_hours')->nullable()->after('opening_hours');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn('business_hours');
        });
    }
};
