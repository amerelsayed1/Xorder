<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('combo_groups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('combo_id')->constrained()->cascadeOnDelete();
            $table->string('name_ar', 150)->nullable();
            $table->string('name_en', 150)->nullable();
            $table->unsignedSmallInteger('max_select')->default(1);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['combo_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('combo_groups');
    }
};
