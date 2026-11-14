<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A restaurant's customers. Built up from placed orders (upserted by phone),
 * so the restaurant accumulates a directory of who ordered, how to reach them,
 * and — via customer_addresses — where they are.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 150)->nullable();
            $table->string('phone', 32)->nullable();
            $table->string('email', 150)->nullable();
            $table->text('note')->nullable();
            $table->timestamps();

            // Upsert key: one customer record per phone within a restaurant.
            $table->unique(['restaurant_id', 'phone']);
            $table->index(['restaurant_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customers');
    }
};
