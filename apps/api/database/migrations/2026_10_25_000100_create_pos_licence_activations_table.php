<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which devices have used a licence's activation key.
 *
 * Until now the platform kept one fact about activation: `pos_licences.activated_at`,
 * the first time anybody used the key. An offline customer has no tenant and no
 * terminals here, so for them the licence page had nothing at all to say about
 * whether the key had ever been put on a machine, which one, or when it last
 * came back (a renewal reaches a till by re-fetching under the same key).
 *
 * One row per (key, device). Keyed on the key's HMAC rather than the licence id
 * so the history survives a renewal, which keeps the key; a rotated key starts
 * a new history, correctly. `fingerprint` is the device's own id as the till
 * reports it, and '' when it did not report one (older tills), so that
 * "unknown device" is one row rather than a null the unique index would let
 * repeat.
 *
 * Additive: a new table, no existing column touched. Licences activated before
 * this keep their `activated_at` and show as "device not recorded".
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('pos_licence_activations')) {
            return;
        }

        Schema::create('pos_licence_activations', function (Blueprint $table) {
            $table->id();
            $table->string('key_hash', 64)->index();
            $table->string('fingerprint', 128)->default('');
            $table->timestamp('first_seen_at');
            $table->timestamp('last_seen_at');
            $table->unsignedInteger('times')->default(1);
            $table->timestamps();

            $table->unique(['key_hash', 'fingerprint']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_licence_activations');
    }
};
