<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // Optional public review destination (Google/TripAdvisor/etc.) shown
            // after private feedback, plus the localized thank-you copy.
            $table->string('review_public_url', 2048)->nullable();
            $table->string('review_thank_you_ar', 500)->nullable();
            $table->string('review_thank_you_en', 500)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn(['review_public_url', 'review_thank_you_ar', 'review_thank_you_en']);
        });
    }
};
