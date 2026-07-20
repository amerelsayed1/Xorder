<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bill_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('dining_area_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('table_id')->nullable()->constrained('dining_tables')->nullOnDelete();
            $table->foreignId('menu_session_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('order_id')->nullable()->constrained()->nullOnDelete();
            // Opaque token the customer uses to poll / cancel their own request.
            $table->string('public_token', 40)->unique();
            $table->string('status', 20)->default('REQUESTED');
            $table->text('customer_note')->nullable();
            $table->string('customer_phone', 32)->nullable();
            // Lifecycle timestamps power the response/completion-time metrics.
            $table->timestamp('requested_at')->nullable();
            $table->timestamp('seen_at')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->foreignId('seen_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('completed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['restaurant_id', 'status']);
            $table->index('table_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bill_requests');
    }
};
