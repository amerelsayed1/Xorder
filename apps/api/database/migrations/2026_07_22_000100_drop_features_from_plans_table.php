<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // The free-text marketing "features" list is retired: a plan is defined
        // entirely by its feature_keys entitlements. The customer-facing pricing
        // bullets live in landing content, not on the Plan model.
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn('features');
        });
    }

    public function down(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->json('features')->nullable()->after('currency');
        });
    }
};
