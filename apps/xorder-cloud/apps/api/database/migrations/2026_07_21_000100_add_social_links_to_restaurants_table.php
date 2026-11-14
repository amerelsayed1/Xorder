<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // Optional public social profile URLs keyed by platform, e.g.
            // {"instagram": "https://…", "facebook": "https://…"}. Only the keys
            // the restaurant fills in are shown in the menu footer — nothing is
            // rendered when this is null/empty.
            $table->json('social_links')->nullable()->after('opening_hours');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('social_links');
        });
    }
};
