<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->string('status', 20)->default('NEW');
            // Cart snapshot: [{name, qty, options: [..], line_total}] — the
            // menu can change later; the order must not.
            $table->json('items');
            $table->decimal('total', 10, 2)->default(0);
            $table->string('currency', 3)->default('EGP');
            $table->string('customer_name', 150)->nullable();
            $table->string('customer_phone', 32)->nullable();
            $table->text('note')->nullable();
            // How the order reached the restaurant (whatsapp for the MVP flow).
            $table->string('source', 40)->default('whatsapp');
            $table->timestamps();

            $table->index(['restaurant_id', 'status']);
            $table->index(['restaurant_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('orders');
    }
};
