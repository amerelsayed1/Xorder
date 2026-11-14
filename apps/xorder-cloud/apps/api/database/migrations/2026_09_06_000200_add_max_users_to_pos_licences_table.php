<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * How many people may hold an account on the customer's tills.
     *
     * The second half of what an offline licence actually sells. There is no
     * feature ladder on an on-premises install — the customer gets the whole
     * product, because gating features on a machine we do not run is a promise
     * we cannot keep. What is sold instead is capacity: how many DEVICES
     * (`max_terminals`, already here) and how many PEOPLE (this).
     *
     * Unlike `max_terminals`, this one is genuinely enforceable on the till: a
     * terminal cannot see its siblings (POS-BE-016, which is why the terminal
     * count is advisory), but every staff row lives in the one database that
     * till is looking at. So the number here is a rule, not a note.
     *
     * Null = unlimited, and that is the correct value for a cloud licence:
     * there the platform counts staff against the tenant's plan server-side,
     * where it can actually be trusted.
     *
     * Additive.
     */
    public function up(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            $table->unsignedSmallInteger('max_users')->nullable()->after('max_terminals');
        });
    }

    public function down(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            $table->dropColumn('max_users');
        });
    }
};
