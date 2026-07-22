<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            // How the public menu takes orders: 'whatsapp' | 'system' | 'both'.
            // Default 'both' preserves the existing behaviour (record + WhatsApp).
            $table->string('ordering_mode', 16)->default('both')->after('ordering_enabled');
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn('ordering_mode');
        });
    }
};
