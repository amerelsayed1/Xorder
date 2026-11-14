<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Let a shared ("global") option group choose how broadly it applies:
 *   - items       → attached one item at a time (the existing pivot; default)
 *   - categories  → auto-applies to every item in the linked categories
 *   - all         → auto-applies to every item in the restaurant (general)
 *
 * `apply_scope` is only meaningful for global groups; inline per-item groups
 * keep the default 'items' and ignore it. Category links live in the new
 * option_group_category pivot so a group can target one OR many categories.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('option_groups', function (Blueprint $table) {
            $table->string('apply_scope', 16)->default('items')->after('is_global')->index();
        });

        Schema::create('option_group_category', function (Blueprint $table) {
            $table->id();
            $table->foreignId('option_group_id')->constrained()->cascadeOnDelete();
            $table->foreignId('category_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['option_group_id', 'category_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('option_group_category');

        Schema::table('option_groups', function (Blueprint $table) {
            $table->dropIndex(['apply_scope']);
            $table->dropColumn('apply_scope');
        });
    }
};
