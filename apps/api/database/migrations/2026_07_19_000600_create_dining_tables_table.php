<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('dining_tables', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->foreignId('dining_area_id')->constrained()->cascadeOnDelete();
            // The table's name or number as shown to staff/customers ("12", "A3").
            $table->string('label', 60);
            $table->unsignedSmallInteger('seats_count')->nullable();
            $table->text('notes')->nullable();
            // Non-sequential, platform-unique token that the QR encodes — never
            // exposes the internal id (FR-QR-004/005, BR-003/004).
            $table->string('public_token', 24)->unique();
            $table->boolean('is_active')->default(true);
            $table->timestamp('qr_generated_at')->nullable();
            $table->timestamps();

            // Table name/number is unique within its dining area (FR-TABLE-003),
            // but may repeat across areas/branches (FR-TABLE-004).
            $table->unique(['dining_area_id', 'label']);
            $table->index(['restaurant_id', 'branch_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('dining_tables');
    }
};
