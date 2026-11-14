<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice c: supplier payments and what they are allocated to.
     *
     * Additive: two brand-new tables, nothing existing changes.
     *
     * - A payment is money that left the business, per branch, to one
     *   supplier. It is ALLOCATED to zero or more of that supplier's
     *   invoices; whatever is not allocated is money paid ON ACCOUNT, which
     *   reduces the balance without clearing any particular bill (the till's
     *   rule, supplier_invoice.dart SupplierAccount).
     *   The till's payment names at most one invoice; `supplier_payment_
     *   allocations` is the general form of the same thing (one invoice is
     *   one allocation row).
     * - An invoice's LIVE allocations can never exceed its total. That is a
     *   cross-row rule, enforced in SupplierLedgerService under a row lock on
     *   the invoice (the till does it in a PL/pgSQL trigger; the platform
     *   runs SQLite and PostgreSQL with the same code, so no triggers). The
     *   index on (supplier_invoice_id) keeps the SUM under that lock cheap.
     * - No balance anywhere. Allocations are never updated: to change one,
     *   void the payment (its allocations stop counting) and enter it again.
     * - The drawer link (design D13, the till's migration 33): a payment made
     *   out of a till's drawer may name the synced pos_cash_movements row it
     *   left through. One pay-out, one LIVE payment: the till uses a partial
     *   unique index; the portable form is `drawer_link_key` = the movement id
     *   while the payment is live and NULL once voided, under a plain unique
     *   index. `pos_cash_movement_id` itself is kept after a void, as history.
     */
    public function up(): void
    {
        Schema::hasTable('supplier_payments') || Schema::create('supplier_payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained();
            $table->foreignId('supplier_id')->constrained();
            $table->string('supplier_name', 160);
            $table->string('method', 16);
            $table->unsignedBigInteger('amount_minor');
            $table->char('currency', 3);
            $table->unsignedTinyInteger('exponent')->default(2);
            $table->string('reference', 120)->nullable();
            $table->date('paid_at');
            $table->text('note')->nullable();
            $table->foreignId('pos_cash_movement_id')->nullable()->constrained('pos_cash_movements')->nullOnDelete();
            $table->unsignedBigInteger('drawer_link_key')->nullable();
            $table->timestamp('voided_at')->nullable();
            $table->foreignId('voided_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('void_reason', 32)->nullable();
            $table->text('void_note')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique('drawer_link_key');
            $table->index(['supplier_id', 'paid_at']);
            $table->index(['restaurant_id', 'branch_id', 'paid_at']);
            $table->index(['restaurant_id', 'reference']);
            $table->index('pos_cash_movement_id');
        });

        Schema::hasTable('supplier_payment_allocations') || Schema::create('supplier_payment_allocations', function (Blueprint $table) {
            $table->id();
            // Stamped from the payment, never from input.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_payment_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_invoice_id')->constrained();
            $table->unsignedBigInteger('amount_minor');
            $table->timestamps();

            $table->unique(['supplier_payment_id', 'supplier_invoice_id']);
            $table->index('supplier_invoice_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('supplier_payment_allocations');
        Schema::dropIfExists('supplier_payments');
    }
};
