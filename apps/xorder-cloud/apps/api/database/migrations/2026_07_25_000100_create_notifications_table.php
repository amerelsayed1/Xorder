<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Durable in-app notification feed for the restaurant dashboard. Unlike the
 * ephemeral toasts (lost on refresh) and best-effort FCM push (opt-in), every
 * notable event is recorded here so the notification centre survives reloads
 * and a fresh device sees what it missed. Tenant-scoped like every other
 * restaurant-owned model.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            // Dotted event key, e.g. 'order.created', 'bill_request.created',
            // 'review.created', 'subscription.expiring'. Drives the icon/route.
            $table->string('type', 40);
            $table->string('title');
            $table->text('body')->nullable();
            // Free-form payload: { url, order_id, bill_request_id, ... }.
            $table->json('data')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();

            // Unread-count and "latest first" reads both hit these.
            $table->index(['restaurant_id', 'read_at']);
            $table->index(['restaurant_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications');
    }
};
