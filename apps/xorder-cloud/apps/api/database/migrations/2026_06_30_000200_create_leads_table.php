<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('leads', function (Blueprint $table) {
            $table->id();
            $table->string('restaurant_name', 150);
            $table->string('contact_name', 150)->nullable();
            $table->string('whatsapp', 40);
            $table->string('city', 100)->nullable();
            $table->string('business_type', 80)->nullable();
            $table->text('message')->nullable();
            // Which page/section produced the lead (e.g. "hero", "lead_form").
            $table->string('source', 120)->nullable();
            // Sales pipeline status — see App\Enums\LeadStatus.
            $table->string('status', 30)->default('NEW');
            // Internal sales notes, never shown publicly.
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index('status');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('leads');
    }
};
