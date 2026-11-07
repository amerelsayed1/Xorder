<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * XORD-015, stage 1: which account a payment method pays into, per branch.
 *
 * One row per (payment method, branch). `branch_id` null is the business-wide
 * fallback. The account for method M at branch B is the row for (M, B), else
 * the row for (M, null), else none. A method with no row behaves exactly as it
 * does today.
 *
 * A plain UNIQUE (tender_type_id, branch_id) would let two business-wide rows
 * in, because NULLs never collide on SQLite or on PostgreSQL. This repo avoids
 * engine-specific SQL (partial indexes), so `branch_key` carries the branch id
 * as a NON-null number, 0 meaning "the whole business", and the unique key is
 * on that. The model keeps it in step with `branch_id`.
 *
 * Additive: a new table. `financial_account_id` has no on-delete action — an
 * account is never deleted, only deactivated.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('tender_account_defaults')) {
            return;
        }

        Schema::create('tender_account_defaults', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('tender_type_id')->constrained('tender_types')->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches')->cascadeOnDelete();
            $table->unsignedBigInteger('branch_key')->default(0);
            $table->foreignId('financial_account_id')->constrained('financial_accounts');
            $table->timestamps();

            $table->unique(['tender_type_id', 'branch_key'], 'tender_account_defaults_method_branch_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tender_account_defaults');
    }
};
