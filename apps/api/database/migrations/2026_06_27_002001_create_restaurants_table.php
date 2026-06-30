<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('restaurants', function (Blueprint $table) {
            $table->id();
            $table->string('name_ar', 150)->nullable();
            $table->string('name_en', 150)->nullable();
            $table->string('slug', 80)->unique();
            $table->text('description_ar')->nullable();
            $table->text('description_en')->nullable();
            $table->string('logo_url')->nullable();
            $table->string('cover_image_url')->nullable();
            $table->string('phone', 32)->nullable();
            $table->string('whatsapp_number', 32)->nullable();
            $table->text('address')->nullable();
            $table->text('opening_hours')->nullable();
            $table->string('brand_color', 7)->default('#111827');
            $table->string('secondary_color', 7)->nullable();
            $table->string('default_language', 2)->default('ar');
            $table->string('status')->default('ACTIVE')->index();
            $table->string('subscription_status')->default('TRIAL');
            $table->string('subscription_plan')->nullable();
            $table->date('subscription_start_date')->nullable();
            $table->date('subscription_end_date')->nullable();
            $table->timestamps();
        });

        // Now that restaurants exists, wire the users.restaurant_id FK.
        Schema::table('users', function (Blueprint $table) {
            $table->foreign('restaurant_id')
                ->references('id')->on('restaurants')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['restaurant_id']);
        });

        Schema::dropIfExists('restaurants');
    }
};
