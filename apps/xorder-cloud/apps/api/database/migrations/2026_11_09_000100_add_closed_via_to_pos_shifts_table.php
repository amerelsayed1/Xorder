<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where a shift was closed: `dashboard` when an owner force-closed a shift
 * whose till was revoked and so can never close it itself
 * (dashboard-shift-details, owner decision 2026-11-09).
 *
 * Nullable and additive: every shift closed before this, and every close a
 * till sends, reads null — "closed at the till". No backfill, no default, so
 * PostgreSQL adds it without rewriting the table.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('pos_shifts', function (Blueprint $table) {
            if (! Schema::hasColumn('pos_shifts', 'closed_via')) {
                $table->string('closed_via', 16)->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('pos_shifts', function (Blueprint $table) {
            if (Schema::hasColumn('pos_shifts', 'closed_via')) {
                $table->dropColumn('closed_via');
            }
        });
    }
};
