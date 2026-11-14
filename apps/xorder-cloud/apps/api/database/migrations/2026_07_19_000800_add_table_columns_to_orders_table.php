<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->foreignId('branch_id')->nullable()->after('restaurant_id')->constrained()->nullOnDelete();
            $table->foreignId('dining_area_id')->nullable()->after('branch_id')->constrained()->nullOnDelete();
            $table->foreignId('table_id')->nullable()->after('dining_area_id')->constrained('dining_tables')->nullOnDelete();
            $table->foreignId('menu_session_id')->nullable()->after('table_id')->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropConstrainedForeignId('branch_id');
            $table->dropConstrainedForeignId('dining_area_id');
            $table->dropConstrainedForeignId('table_id');
            $table->dropConstrainedForeignId('menu_session_id');
        });
    }
};
