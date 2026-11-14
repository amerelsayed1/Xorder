<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice b: purchase orders, their lines, and the reference
     * sequence. The platform copy of the till's migration 28.
     *
     * Additive: three brand-new tables, nothing existing changes.
     *
     * - Per BRANCH: stock that arrived at Downtown is not stock Maadi can use.
     * - `branch_id` and `supplier_id` use the default NO ACTION, not RESTRICT:
     *   both block deleting a branch or supplier an order points at, but NO
     *   ACTION is checked at the end of the statement, so a restaurant's own
     *   cascade delete can still remove its orders and its branches together.
     *   (Suppliers have no delete route at all; they are retired.)
     * - `supplier_name` and each line's `description` are snapshots, so the
     *   paper still reads the same after a rename.
     * - `reference` is NULL while the order is a draft. The number is consumed
     *   at SEND (PurchaseSequenceService), so a thrown-away draft leaves no
     *   gap; NULLs are distinct in unique(restaurant_id, reference).
     * - Totals are snapshotted at send. Money is integer minor units and a
     *   quantity integer thousandths, as on the till; rates are basis points.
     * - Every status change goes through PurchaseOrderService /
     *   ReceivingService under a lock on the order row. There is no CHECK:
     *   Blueprint has none that is portable, and the till's own CHECK-less
     *   setStatus is exactly the gap the platform closes (design §10 C2).
     */
    public function up(): void
    {
        Schema::create('purchase_orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained();
            $table->foreignId('supplier_id')->constrained();
            $table->string('supplier_name', 160);
            $table->string('reference', 32)->nullable();
            $table->string('status', 20)->default('draft');
            $table->char('currency', 3);
            $table->unsignedTinyInteger('exponent')->default(2);
            $table->unsignedBigInteger('subtotal_minor')->default(0);
            $table->unsignedBigInteger('tax_minor')->default(0);
            $table->unsignedBigInteger('total_minor')->default(0);
            $table->timestamp('ordered_at')->nullable();
            $table->date('expected_at')->nullable();
            $table->text('notes')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['restaurant_id', 'reference']);
            $table->index(['restaurant_id', 'branch_id', 'status']);
            $table->index(['supplier_id', 'ordered_at']);
        });

        Schema::create('purchase_order_lines', function (Blueprint $table) {
            $table->id();
            // Stamped from the order, never from input.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('purchase_order_id')->constrained()->cascadeOnDelete();
            // NULL for what a business buys but doesn't count (packaging, gas).
            $table->foreignId('stock_item_id')->nullable()->constrained()->nullOnDelete();
            $table->string('description', 200);
            $table->string('sku', 64)->nullable();
            $table->bigInteger('ordered_milli');
            $table->bigInteger('received_milli')->default(0);
            $table->string('unit_code', 16)->default('ea');
            $table->unsignedBigInteger('unit_cost_minor');
            $table->unsignedInteger('tax_rate_bp')->default(0);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['purchase_order_id', 'sort_order']);
            $table->index('stock_item_id');
        });

        Schema::create('purchase_sequences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('period', 8);
            $table->unsignedBigInteger('next_value')->default(1);
            $table->timestamps();

            $table->unique(['restaurant_id', 'period']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('purchase_sequences');
        Schema::dropIfExists('purchase_order_lines');
        Schema::dropIfExists('purchase_orders');
    }
};
