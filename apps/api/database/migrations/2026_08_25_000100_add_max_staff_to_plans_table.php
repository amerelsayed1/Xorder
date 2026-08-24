<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * How many staff accounts a plan allows, alongside the existing item,
     * category and branch caps.
     *
     * Nullable and left null for every existing plan on purpose: null means
     * unlimited, so no live tenant is retroactively capped by a deploy. A plan
     * only starts limiting once someone sets a number on it.
     *
     * The owner is not counted — they are the account that bought the plan, not
     * a seat sold under it.
     */
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->unsignedInteger('max_staff')->nullable()->after('max_branches');
        });
    }

    public function down(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn('max_staff');
        });
    }
};
