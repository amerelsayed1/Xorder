<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // IANA timezone (e.g. "Africa/Cairo") used to bucket orders into
            // day-part report periods by their local timestamp (BR-010/011).
            // Null falls back to config('app.timezone').
            $table->string('timezone', 64)->nullable()->after('currency');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('timezone');
        });
    }
};
