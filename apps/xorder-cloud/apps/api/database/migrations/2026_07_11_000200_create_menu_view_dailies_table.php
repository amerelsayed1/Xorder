<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // One row per restaurant per day — first-party menu-view analytics
        // for the owner dashboard without any external tracker.
        Schema::create('menu_view_dailies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->date('date');
            $table->unsignedInteger('views')->default(0);
            $table->timestamps();

            $table->unique(['restaurant_id', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_view_dailies');
    }
};
