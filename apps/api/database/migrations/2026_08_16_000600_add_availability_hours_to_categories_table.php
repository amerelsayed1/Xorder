<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Per-weekday serving times for a category — breakfast until 11:00, the
     * shisha menu after 18:00, and so on.
     *
     * Same shape as the branch/restaurant business_hours (sat..fri →
     * { closed, always, open, close }) so the dashboard reuses the existing
     * hours editor and there is one schedule format in the product rather than
     * two. Null means no restriction, which is every category that exists
     * today, so nothing changes for them.
     */
    public function up(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->json('availability_hours')->nullable()->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->dropColumn('availability_hours');
        });
    }
};
