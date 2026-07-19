<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A table-bound browsing session created when a customer scans a table QR
     * (FR-SESSION-001). Orders and, later, bill requests link back to it so the
     * restaurant knows which physical table an action came from.
     */
    public function up(): void
    {
        Schema::create('menu_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('dining_area_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('table_id')->nullable()->constrained('dining_tables')->nullOnDelete();
            $table->string('session_token', 40)->unique();
            $table->string('language', 2)->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('last_activity_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->index('table_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_sessions');
    }
};
