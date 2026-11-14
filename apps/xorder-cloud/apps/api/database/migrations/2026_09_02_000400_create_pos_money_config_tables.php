<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-013 — the server becomes the author of everything that decides how
     * much money is owed. Three tenant-scoped tables; authored from the
     * dashboard, delivered read-only in the bootstrap bundle.
     *
     * Money discipline (D1): rates are integer BASIS POINTS (1400 = 14%),
     * fixed amounts are integer MINOR UNITS. Never a float, never decimal.
     *
     * tender_types are never hard-deleted once referenced by a payment —
     * DELETE deactivates (is_active = false) so historical order_payments keep
     * their FK. applies_to is a json scope object {order_types, branch_ids,
     * category_ids, item_ids}; [] anywhere means "all".
     */
    public function up(): void
    {
        Schema::create('tax_rules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->unsignedInteger('rate_bp');
            $table->string('mode', 12)->default('exclusive'); // inclusive | exclusive
            $table->json('applies_to')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('charges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('kind', 12); // percent | fixed
            $table->unsignedInteger('rate_bp')->nullable();      // percent kind
            $table->unsignedBigInteger('amount_minor')->nullable(); // fixed kind
            $table->boolean('taxable')->default(false);
            $table->json('applies_to')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });

        Schema::create('tender_types', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('kind', 12); // cash | card | external | other
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tender_types');
        Schema::dropIfExists('charges');
        Schema::dropIfExists('tax_rules');
    }
};
