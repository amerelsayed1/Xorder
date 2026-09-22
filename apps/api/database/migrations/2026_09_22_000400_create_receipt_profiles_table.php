<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A3 — who the receipt says sold the food, per branch.
     *
     * `PosBootstrapService::bundle()` delivered `invoice{}` and `branding{}` but
     * no receipt profile, so every cloud till printed with compiled-in
     * defaults. This is the platform's half of CB-08: the platform authors the
     * legal identity on the slip, the till reads it.
     *
     * **The column names are the till's, deliberately** — they mirror
     * `pos_receipt_profiles` in `xorder-pos/lib/data/postgres/migrations.dart`
     * one for one (including ETA's spelling, `governate`, and the short
     * `additional_info`), so the POS bootstrap seeder is a straight mapping
     * with no translation table for anyone to get wrong later. Two names are
     * worth reading twice:
     *
     *   branch_code   the branch as the TAX AUTHORITY knows it. NOT
     *                 `branches.code`, which is the invoice prefix and the
     *                 restaurant's to choose. Keeping them apart costs one text
     *                 box and saves the day somebody renames a prefix.
     *   country       two-letter ISO, defaulted to EG rather than to empty: a
     *                 blank country is never the right answer.
     *
     * There is **no registration_number column here.** The taxpayer's
     * registration number is one fact about one taxpayer, it already lives on
     * `restaurants.tax_registration_number`, and a second copy per branch would
     * be a second author of one row. The bundle projects the restaurant's
     * number into every profile's `registration_number` field.
     *
     * Everything is NOT NULL with a '' default, matching the till: a
     * half-entered profile is the normal way one is filled in, and a CHECK or a
     * NULL would either forbid that or force every reader to handle it.
     */
    public function up(): void
    {
        Schema::create('receipt_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->string('trade_name', 150)->default('');
            $table->string('activity_code', 8)->default('');
            $table->string('branch_code', 32)->default('');
            $table->string('country', 2)->default('EG');
            $table->string('governate', 80)->default('');
            $table->string('region_city', 80)->default('');
            $table->string('street', 150)->default('');
            $table->string('building_number', 32)->default('');
            $table->string('postal_code', 16)->default('');
            $table->string('floor', 16)->default('');
            $table->string('room', 16)->default('');
            $table->string('landmark', 150)->default('');
            $table->string('additional_info', 255)->default('');
            $table->string('phone', 32)->default('');
            $table->text('header_note')->nullable();
            $table->text('footer_note')->nullable();
            // Bumped on every save and checked on the next: an office and a
            // counter editing one profile is not hypothetical.
            $table->unsignedInteger('revision')->default(0);
            $table->foreignId('updated_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            // One profile per branch. The receipt has one header.
            $table->unique('branch_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('receipt_profiles');
    }
};
