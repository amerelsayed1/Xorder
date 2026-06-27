<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_items', function (Blueprint $table) {
            $table->id();
            // restaurant_id denormalized for fast tenant scoping + public query.
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('category_id')->constrained()->cascadeOnDelete();
            $table->string('name_ar', 150)->nullable();
            $table->string('name_en', 150)->nullable();
            $table->text('description_ar')->nullable();
            $table->text('description_en')->nullable();
            $table->decimal('price', 10, 2);
            $table->decimal('discounted_price', 10, 2)->nullable();
            $table->string('image_url')->nullable();
            $table->boolean('is_available')->default(true);
            $table->boolean('is_featured')->default(false);
            $table->integer('display_order')->default(0);
            $table->softDeletes();
            $table->timestamps();

            $table->index(['restaurant_id', 'category_id', 'display_order']);
            $table->index(['restaurant_id', 'is_featured']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_items');
    }
};
