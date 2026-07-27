<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('plans', 'is_recommended')) {
            return;
        }

        Schema::table('plans', function (Blueprint $table) {
            // Marks the plan highlighted as "Recommended" on the public landing
            // pricing grid. Purely presentational — it does not affect
            // entitlements. At most one plan is normally flagged.
            $table->boolean('is_recommended')->default(false)->after('is_active');
        });
    }

    public function down(): void
    {
        if (! Schema::hasColumn('plans', 'is_recommended')) {
            return;
        }

        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn('is_recommended');
        });
    }
};
