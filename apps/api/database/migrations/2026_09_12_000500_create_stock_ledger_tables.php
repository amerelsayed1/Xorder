<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice b: the stock ledger and the per-branch level. The platform
     * copy of the till's migration 29.
     *
     * Additive: two brand-new tables, nothing existing changes.
     *
     * stock_movements is APPEND-ONLY. No route updates or deletes one, and
     * the model's updating/deleting events throw. Quantity is signed
     * thousandths. Each movement records the RESULTING balance and moving
     * average, so the level can always be checked by replaying the ledger
     * (StockLedger::replay). Slice b writes only kind `receipt`.
     *
     * stock_levels is a justified cache, keyed unique(branch_id,
     * stock_item_id): a moving average is a fold, not something a SUM can
     * recompute. It is written only by ReceivingService, in the same
     * transaction as the movement, under a row lock, and always equals the
     * last movement's balance and average.
     *
     * Neither is "on hand": tills don't deduct stock when they sell (D4), so
     * the figure is what was received to date.
     */
    public function up(): void
    {
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            // NO ACTION (see the purchase_orders migration): blocks deleting a
            // branch with history, lets a restaurant's cascade through.
            $table->foreignId('branch_id')->constrained();
            $table->foreignId('stock_item_id')->constrained();
            $table->string('kind', 16);
            $table->bigInteger('quantity_milli');
            $table->string('unit_code', 16);
            $table->unsignedBigInteger('unit_cost_minor');
            $table->bigInteger('balance_milli');
            $table->unsignedBigInteger('average_cost_minor');
            $table->foreignId('purchase_order_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('purchase_order_line_id')->nullable()->constrained()->nullOnDelete();
            $table->string('reason', 32)->nullable();
            $table->text('note')->nullable();
            $table->timestamp('occurred_at');
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            // Append-only: a created_at and no updated_at.
            $table->timestamp('created_at')->nullable();

            $table->index(['stock_item_id', 'branch_id', 'occurred_at', 'id']);
            $table->index(['restaurant_id', 'branch_id', 'occurred_at']);
        });

        Schema::create('stock_levels', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained();
            $table->foreignId('stock_item_id')->constrained();
            $table->bigInteger('quantity_milli')->default(0);
            $table->string('unit_code', 16);
            $table->unsignedBigInteger('average_cost_minor')->default(0);
            $table->timestamp('updated_at')->nullable();

            $table->unique(['branch_id', 'stock_item_id']);
            $table->index(['restaurant_id', 'branch_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_levels');
        Schema::dropIfExists('stock_movements');
    }
};
