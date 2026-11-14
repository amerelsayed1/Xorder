<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // The two ordering channels are now mutually exclusive — 'both' is gone.
        // Collapse any restaurant still on 'both' to 'whatsapp' (raw update, so no
        // model events / audit-log writes fire during the migration transaction).
        DB::table('restaurants')->where('ordering_mode', 'both')->update(['ordering_mode' => 'whatsapp']);

        // Retire the old blanket default; new restaurants start on 'whatsapp'.
        Schema::table('restaurants', function (Blueprint $table) {
            $table->string('ordering_mode', 16)->default('whatsapp')->change();
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->string('ordering_mode', 16)->default('both')->change();
        });
        // No-op on the data: the collapsed 'both' rows cannot be reconstructed.
    }
};
