<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-001 — how many POS terminals a plan allows, following the
     * max_staff precedent exactly. Nullable = unlimited, so no existing plan
     * (or tenant) is retroactively capped. Exceeding the count WARNS at claim
     * time, never refuses (POS-BE-016) — refusing to register the sixth till
     * mid-service is the "brick a POS" failure mode.
     */
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->unsignedInteger('max_terminals')->nullable()->after('max_staff');
        });
    }

    public function down(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn('max_terminals');
        });
    }
};
