<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();

            // Tenant the event belongs to. Null for platform-level events that
            // aren't scoped to one restaurant (e.g. a super-admin logging in).
            $table->foreignId('restaurant_id')->nullable()->constrained()->nullOnDelete();

            // Who performed it. Null for anonymous/customer/system actions.
            // actor_name/actor_role are denormalised so the record stays
            // meaningful even after the user row is deleted.
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('actor_name')->nullable();
            $table->string('actor_role', 40)->nullable();

            // Dotted action key, e.g. auth.login, restaurant.status_changed,
            // menu_item.updated, order.status_changed.
            $table->string('action', 80);

            // The affected model (polymorphic), when there is one.
            $table->nullableMorphs('auditable');

            // Human-readable summary + structured detail (old/new changes, etc.).
            $table->text('description')->nullable();
            $table->json('properties')->nullable();

            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();

            $table->timestamps();

            $table->index(['restaurant_id', 'created_at']);
            $table->index(['actor_id', 'created_at']);
            $table->index(['action', 'created_at']);
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
