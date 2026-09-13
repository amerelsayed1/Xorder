<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice c: supplier invoices. The platform copy of the till's
     * migration 30 (pos_supplier_invoices), plus optional lines.
     *
     * Additive: two brand-new tables, nothing existing changes.
     *
     * - Per BRANCH, against a supplier, optionally billing one purchase order.
     * - NO subtotal column and NO balance column, as on the till: the subtotal
     *   is total − tax, and what is outstanding is derived from the live
     *   payments allocated to it (SupplierAccount). A stored copy of either
     *   would part company with the rows the first time a payment was voided.
     * - An invoice NEVER reprices stock. Receiving costed the goods at the
     *   ordered price; an invoice that disagrees is a variance to look at,
     *   not a rewrite of the moving average (till supplier_invoice.dart).
     * - The supplier's number is unique per supplier among LIVE invoices. The
     *   till does that with a partial index (WHERE voided_at IS NULL); the
     *   portable form is `active_number_key` = lower(trim(number)) while live
     *   and NULL once voided, under a plain unique index. NULLs are distinct
     *   in a unique index on both SQLite and PostgreSQL, so a voided number
     *   can be entered again and a live duplicate can't.
     * - `branch_id`, `supplier_id` use NO ACTION (block deleting what an
     *   invoice points at, but let a whole business cascade away cleanly);
     *   `purchase_order_id` is SET NULL with its reference snapshotted, as on
     *   the till.
     * - Voided, never deleted. The reason is one of the till's six
     *   invoice_void codes (App\Enums\InvoiceVoidReason).
     * - Lines are OPTIONAL. The till's invoice has none: a bookkeeper types a
     *   total and a tax off the paper. When lines are given, the total and
     *   tax are computed from them with the till's rounding points (costAt
     *   per line, tax per rate), never typed. Lines carry no stock item: they
     *   are what the paper says, and they cost nothing in stock.
     */
    public function up(): void
    {
        Schema::create('supplier_invoices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained();
            $table->foreignId('supplier_id')->constrained();
            $table->string('supplier_name', 160);
            $table->foreignId('purchase_order_id')->nullable()->constrained()->nullOnDelete();
            $table->string('purchase_order_reference', 32)->nullable();
            $table->string('number', 64);
            $table->string('active_number_key', 64)->nullable();
            $table->char('currency', 3);
            $table->unsignedTinyInteger('exponent')->default(2);
            $table->unsignedBigInteger('total_minor');
            $table->unsignedBigInteger('tax_minor')->default(0);
            $table->date('issued_at');
            $table->date('due_at');
            $table->text('note')->nullable();
            $table->timestamp('voided_at')->nullable();
            $table->foreignId('voided_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('void_reason', 32)->nullable();
            $table->text('void_note')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['restaurant_id', 'supplier_id', 'active_number_key']);
            $table->index(['restaurant_id', 'branch_id', 'due_at']);
            $table->index(['supplier_id', 'issued_at']);
            $table->index('purchase_order_id');
        });

        Schema::create('supplier_invoice_lines', function (Blueprint $table) {
            $table->id();
            // Stamped from the invoice, never from input.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('supplier_invoice_id')->constrained()->cascadeOnDelete();
            $table->string('description', 200);
            $table->bigInteger('quantity_milli');
            $table->unsignedBigInteger('unit_cost_minor');
            $table->unsignedInteger('tax_rate_bp')->default(0);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['supplier_invoice_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('supplier_invoice_lines');
        Schema::dropIfExists('supplier_invoices');
    }
};
