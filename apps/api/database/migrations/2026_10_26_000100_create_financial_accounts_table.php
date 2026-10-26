<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * XORD-015, stage 1: the places a business keeps its money — a cash drawer, a
 * bank account, an e-wallet — each optionally tied to one branch.
 *
 * Additive: a new table, no existing column touched, nothing posted to it.
 *
 *  - `branch_id` is nullable (null = shared by the whole business) and has NO
 *    on-delete action. It must not be `nullOnDelete`: removing a branch would
 *    silently turn its drawer into a business-wide account. NO ACTION (the
 *    default) is checked at the end of the statement, so deleting a restaurant,
 *    which cascades to both branches and accounts, still works on PostgreSQL.
 *  - `currency` is the restaurant's currency, set by the server, never typed.
 *  - `reference_label` is a short human hint ("CIB ••4521"). It is not an
 *    account number and the API refuses anything that looks like one.
 *  - Accounts are never deleted; `is_active` is the way out, so a later
 *    payment or movement that names one keeps a row to point at.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('financial_accounts')) {
            return;
        }

        Schema::create('financial_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches');
            $table->string('name', 120);
            $table->string('kind', 8); // cash | bank | wallet
            $table->string('currency', 3);
            $table->string('reference_label', 40)->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['restaurant_id', 'name']);
            $table->index(['restaurant_id', 'branch_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('financial_accounts');
    }
};
