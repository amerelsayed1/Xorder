<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // Structured weekly opening hours keyed by day short-name
            // ("sun".."sat"), each {"closed": bool, "open": "HH:MM", "close":
            // "HH:MM"}. Powers the menu "info" sheet and the open/closed badge.
            // The legacy free-text opening_hours column is kept as a fallback.
            $table->json('business_hours')->nullable()->after('opening_hours');

            // Estimated delivery window in minutes (e.g. 25–35). Both null hides
            // the delivery row entirely.
            $table->unsignedSmallInteger('delivery_time_min')->nullable()->after('business_hours');
            $table->unsignedSmallInteger('delivery_time_max')->nullable()->after('delivery_time_min');

            // Minimum order value for delivery, in the restaurant's currency.
            $table->decimal('minimum_order', 10, 2)->nullable()->after('delivery_time_max');

            // Optional map pin used for the embedded map + directions link.
            $table->decimal('latitude', 10, 7)->nullable()->after('minimum_order');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn([
                'business_hours',
                'delivery_time_min',
                'delivery_time_max',
                'minimum_order',
                'latitude',
                'longitude',
            ]);
        });
    }
};
