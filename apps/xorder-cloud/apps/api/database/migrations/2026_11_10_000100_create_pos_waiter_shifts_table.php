<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * POS-BE-033 — the waiter shift clock. Additive only: one new table.
 *
 * A shift is the waiter's (the user's), not the phone's; the device that
 * started it and the one that finished it are recorded for the manager's
 * report and survive the device being deleted (nullOnDelete).
 *
 * One open shift per waiter is a partial unique index (`ended_at IS NULL`),
 * which PostgreSQL (prod) and SQLite (dev/test) both support with the same
 * statement; the service also checks first, the index is the race guard.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pos_waiter_shifts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('started_device_id')->nullable()->constrained('pos_waiter_devices')->nullOnDelete();
            $table->foreignId('ended_device_id')->nullable()->constrained('pos_waiter_devices')->nullOnDelete();
            $table->timestamp('started_at');
            $table->timestamp('ended_at')->nullable();
            $table->timestamps();

            $table->index(['restaurant_id', 'user_id', 'ended_at']);
            $table->index(['restaurant_id', 'started_at']);
        });

        DB::statement('CREATE UNIQUE INDEX pos_waiter_shifts_one_open ON pos_waiter_shifts (user_id) WHERE ended_at IS NULL');
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_waiter_shifts');
    }
};
