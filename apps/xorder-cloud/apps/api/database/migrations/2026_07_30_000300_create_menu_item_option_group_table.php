<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Pivot linking menu items to reusable ("global") option groups. A global group
 * can be attached to many items; each attachment carries its own display order.
 * restaurant_id is stored on the pivot too so tenant-scoped queries never have
 * to join back through the parents.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_item_option_group', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('option_group_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->unique(['menu_item_id', 'option_group_id']);
            $table->index(['menu_item_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_item_option_group');
    }
};
