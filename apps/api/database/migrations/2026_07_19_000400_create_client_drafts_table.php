<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A partially-configured client held by the creation wizard before it is
     * provisioned. A draft deliberately claims no slug and creates no user or
     * restaurant row (BR-CLIENT-012) — those only come into existence when the
     * wizard calls RestaurantProvisioningService at completion. The whole
     * in-progress payload lives in `form_data` (JSON), which keeps step schema
     * churn out of the relational model.
     */
    public function up(): void
    {
        Schema::create('client_drafts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('created_by')->constrained('users')->cascadeOnDelete();
            $table->unsignedTinyInteger('current_step')->default(1);
            $table->json('form_data')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->index('created_by');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('client_drafts');
    }
};
