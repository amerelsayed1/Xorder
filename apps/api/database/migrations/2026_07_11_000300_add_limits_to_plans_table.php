<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            // null = unlimited. Enforced on dashboard creates by PlanLimitService.
            $table->unsignedInteger('max_items')->nullable()->after('features');
            $table->unsignedInteger('max_branches')->nullable()->after('max_items');
        });
    }

    public function down(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn(['max_items', 'max_branches']);
        });
    }
};
