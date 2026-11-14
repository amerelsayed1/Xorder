<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Delivery addresses for a customer — one customer can have many (home, work,
 * a friend's place). restaurant_id is denormalized so the row is tenant-scoped
 * like the rest of the menu data.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_addresses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('customer_id')->constrained()->cascadeOnDelete();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('label', 60)->nullable();   // e.g. Home, Work
            $table->string('address', 500);
            $table->text('note')->nullable();
            $table->boolean('is_default')->default(false);
            $table->timestamps();

            $table->index('restaurant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_addresses');
    }
};
