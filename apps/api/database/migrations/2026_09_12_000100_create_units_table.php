<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * CB-09 slice a: the units a client counts and buys stock in. The platform
     * copy of the till's pos_units (xorder-pos migration 39).
     *
     * Additive: a brand-new table, nothing existing changes.
     *
     * - `code` is what every later purchasing row stores (purchase lines and
     *   stock rows keep a unit code, never an id), so it is immutable once
     *   written. The shape rule (^[a-z][a-z0-9_]{0,15}$) lives in the
     *   FormRequest: Blueprint has no CHECK, and SQLite and PostgreSQL spell a
     *   regex CHECK differently.
     * - There is no delete. A unit is retired with is_active = false, because
     *   a code already written on a purchase line must keep meaning something.
     * - The seven defaults are created lazily by App\Services\UnitCatalog, not
     *   here: a migration that seeded every existing tenant would write rows
     *   for businesses that never bought purchasing.
     */
    public function up(): void
    {
        Schema::create('units', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 16);
            // Either name may be absent, but not both (FormRequest), as with
            // every other bilingual record on the platform.
            $table->string('name_en', 120)->nullable();
            $table->string('name_ar', 120)->nullable();
            // What an e-receipt says the thing was measured in (UN/ECE codes).
            $table->string('eta_unit_type', 6)->default('EA');
            $table->boolean('allows_fraction')->default(false);
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['restaurant_id', 'code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('units');
    }
};
