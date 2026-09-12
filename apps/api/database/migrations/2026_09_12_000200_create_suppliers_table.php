<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice a: who a client buys from. The platform copy of the till's
     * pos_suppliers (xorder-pos migration 27).
     *
     * Additive: a brand-new table, nothing existing changes.
     *
     * - **No balance column, ever.** What a client owes a supplier is derived
     *   from invoices and payments (slice c). A stored balance is a second
     *   copy of the truth that drifts.
     * - `code` is NULLABLE where the till stores ''. SQLite and PostgreSQL
     *   both treat NULLs as distinct in a unique index, so a plain
     *   unique(restaurant_id, code) gives "unique when set, any number
     *   without" with no partial index (which the two engines spell
     *   differently). The FormRequest folds '' to NULL.
     * - `tax_number` is exactly nine digits when present (FormRequest, after
     *   folding Arabic-Indic digits).
     * - There is no delete. A supplier is retired with is_active = false:
     *   purchase orders, invoices and payments (slices b and c) will point at
     *   it with ON DELETE RESTRICT.
     */
    public function up(): void
    {
        Schema::create('suppliers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            // Either name may be absent, but not both (FormRequest).
            $table->string('name_en', 160)->nullable();
            $table->string('name_ar', 160)->nullable();
            $table->string('code', 40)->nullable();
            $table->string('contact_name', 160)->nullable();
            $table->string('phone', 40)->nullable();
            $table->string('email', 255)->nullable();
            $table->text('address')->nullable();
            $table->string('tax_number', 9)->nullable();
            $table->unsignedInteger('payment_term_days')->default(0);
            $table->text('notes')->nullable();
            $table->boolean('is_active')->default(true);
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['restaurant_id', 'code']);
            $table->index(['restaurant_id', 'is_active', 'name_en']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('suppliers');
    }
};
