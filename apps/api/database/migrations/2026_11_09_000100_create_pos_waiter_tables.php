<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * POS-BE-033 — the waiter wire served by the platform. Additive only: three new
 * tables and one defaulted column; nothing existing is altered or backfilled.
 *
 *  - pos_waiter_devices   a phone registered by its first sign-in (token stored hashed)
 *  - pos_waiter_sessions  one signed-in waiter on one device (token stored hashed, idles out)
 *  - table_check_drafts   the unsent lines of a table visit, shared by every device at the table
 *  - table_visits.check_version  compare-and-swap counter for the wire's CHECK_CHANGED
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pos_waiter_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('token_hash', 64)->unique();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            $table->index(['restaurant_id', 'revoked_at']);
        });

        Schema::create('pos_waiter_sessions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('device_id')->constrained('pos_waiter_devices')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('token_hash', 64)->unique();
            $table->timestamp('last_seen_at');
            $table->timestamps();
        });

        Schema::create('table_check_drafts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('table_visit_id')->unique()->constrained('table_visits')->cascadeOnDelete();
            $table->json('lines');
            $table->unsignedSmallInteger('guests')->nullable();
            $table->timestamps();
        });

        Schema::table('table_visits', function (Blueprint $table) {
            $table->unsignedInteger('check_version')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('table_visits', function (Blueprint $table) {
            $table->dropColumn('check_version');
        });
        Schema::dropIfExists('table_check_drafts');
        Schema::dropIfExists('pos_waiter_sessions');
        Schema::dropIfExists('pos_waiter_devices');
    }
};
