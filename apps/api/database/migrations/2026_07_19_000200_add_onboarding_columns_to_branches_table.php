<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->string('code', 40)->nullable()->after('name_en');
            $table->string('city', 120)->nullable()->after('address');
            $table->string('country', 2)->nullable()->after('city');
            // Bilingual address alongside the existing single `address` column,
            // populated for bilingual clients (FR-BRANCH-004). `address` stays
            // as the legacy/primary value so nothing existing breaks.
            $table->text('address_ar')->nullable()->after('address');
            $table->text('address_en')->nullable()->after('address_ar');
            // Order types this branch accepts: dine_in | pickup | delivery
            // (FR-BRANCH-005). Null on legacy rows = unconstrained.
            $table->json('supported_order_types')->nullable()->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn([
                'code', 'city', 'country', 'address_ar', 'address_en', 'supported_order_types',
            ]);
        });
    }
};
