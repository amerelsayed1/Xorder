<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            // Machine-readable entitlement set: the Feature enum values this plan
            // grants. Distinct from `features` (human-readable marketing strings).
            // A restaurant's restaurant_features rows are derived from its plan's
            // feature_keys — the plan strictly decides which capabilities appear.
            $table->json('feature_keys')->nullable()->after('features');
        });
    }

    public function down(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn('feature_keys');
        });
    }
};
