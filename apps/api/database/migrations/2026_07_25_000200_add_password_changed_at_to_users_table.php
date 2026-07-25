<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Records when a user's password last changed so the stateless JWT guard can
 * reject any access token minted before that moment. Without this, a password
 * reset/change does not invalidate already-issued tokens (default TTL 7 days),
 * leaving a stolen token usable long after the victim "recovers" the account.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('password_changed_at')->nullable()->after('password');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('password_changed_at');
        });
    }
};
