<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('table_visits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('dining_area_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('table_id')->constrained('dining_tables')->cascadeOnDelete();
            $table->string('status', 20)->default('OPEN');
            $table->timestamp('opened_at');
            $table->timestamp('closed_at')->nullable();
            $table->foreignId('closed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['restaurant_id', 'status']);
            $table->index(['table_id', 'status']);
        });

        Schema::table('menu_sessions', function (Blueprint $table) {
            $table->foreignId('table_visit_id')->nullable()->after('table_id')
                ->constrained('table_visits')->nullOnDelete();
            $table->timestamp('closed_at')->nullable()->after('expires_at');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->foreignId('table_visit_id')->nullable()->after('menu_session_id')
                ->constrained('table_visits')->nullOnDelete();
            $table->index(['table_visit_id', 'status']);
        });

        Schema::create('order_rounds', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('menu_session_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedInteger('sequence');
            $table->decimal('total', 10, 2);
            $table->text('note')->nullable();
            $table->timestamp('submitted_at');
            $table->timestamps();

            $table->unique(['order_id', 'sequence']);
        });

        Schema::create('order_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_id')->constrained()->cascadeOnDelete();
            $table->foreignId('order_round_id')->constrained()->cascadeOnDelete();
            $table->string('name', 200);
            $table->unsignedSmallInteger('quantity');
            $table->json('options')->nullable();
            $table->text('note')->nullable();
            $table->decimal('unit_price', 10, 2);
            $table->decimal('line_total', 10, 2);
            $table->timestamps();

            $table->index(['order_id', 'order_round_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_items');
        Schema::dropIfExists('order_rounds');

        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['table_visit_id', 'status']);
            $table->dropConstrainedForeignId('table_visit_id');
        });

        Schema::table('menu_sessions', function (Blueprint $table) {
            $table->dropConstrainedForeignId('table_visit_id');
            $table->dropColumn('closed_at');
        });

        Schema::dropIfExists('table_visits');
    }
};
