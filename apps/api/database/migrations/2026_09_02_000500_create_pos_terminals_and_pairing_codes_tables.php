<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-023 / POS-BE-011 / POS-BE-022 — the terminal registry.
     *
     * The platform PROVISIONS the terminal, the till CLAIMS it: the row exists
     * before the machine does, which is what makes fleet tracking structural
     * rather than best-effort (state provisioned → active → revoked).
     *
     * device_token_hash — HMAC-SHA256 of the xdt_ device credential, same
     * discipline as pos_licences.key_hash: deterministic and indexable so the
     * middleware can find the row from the token alone, useless in a stolen
     * dump without APP_KEY. previous_token_hash + device_token_rotated_at give
     * rotation a 24h overlap so a crash between receiving and persisting a new
     * token cannot brick the till.
     *
     * pos_pairing_codes — the claim credential. Hashed at rest, single-use,
     * 24h TTL. response_cache holds the ENCRYPTED claim response (device token
     * included) so a timed-out claim that retries with the same code gets a
     * byte-identical reply rather than a second terminal; purged at expiry.
     */
    public function up(): void
    {
        Schema::create('pos_terminals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('branch_id')->constrained()->cascadeOnDelete();
            $table->uuid('terminal_id');
            $table->string('name', 60);
            $table->string('state', 16)->default('provisioned'); // provisioned | active | revoked
            $table->string('platform', 20)->nullable();
            $table->string('app_version', 32)->nullable();
            $table->string('fingerprint')->nullable();
            $table->string('deployment_mode', 20)->default('cloud');
            $table->string('sync_policy', 20)->default('dynamic');

            $table->char('device_token_hash', 64)->nullable()->index();
            $table->char('previous_token_hash', 64)->nullable()->index();
            $table->timestamp('device_token_rotated_at')->nullable();

            // Path B (register) idempotency + its cached response.
            $table->uuid('client_transaction_id')->nullable();
            $table->text('register_response_cache')->nullable();

            $table->timestamp('claimed_at')->nullable();
            $table->timestamp('revoked_at')->nullable();

            // Heartbeat, last write wins (POS-BE-022).
            $table->timestamp('last_seen_at')->nullable();
            $table->unsignedInteger('pending_count')->nullable();
            $table->timestamp('oldest_pending_at')->nullable();
            $table->boolean('shift_open')->nullable();
            $table->integer('clock_offset_seconds')->nullable();
            $table->timestamp('last_catalog_sync_at')->nullable();
            $table->timestamp('reported_licence_expires_at')->nullable();

            $table->timestamps();

            $table->unique(['restaurant_id', 'terminal_id']);
            $table->unique(['restaurant_id', 'client_transaction_id']);
        });

        Schema::create('pos_pairing_codes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('restaurant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('pos_terminal_id')->constrained('pos_terminals')->cascadeOnDelete();
            $table->char('code_hash', 64)->index();
            $table->timestamp('expires_at');
            $table->timestamp('used_at')->nullable();
            $table->string('used_fingerprint')->nullable();
            $table->text('response_cache')->nullable();
            $table->foreignId('created_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_pairing_codes');
        Schema::dropIfExists('pos_terminals');
    }
};
