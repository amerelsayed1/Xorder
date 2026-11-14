<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The activation key, kept — encrypted at rest — so Super Admin can copy it
 * again (owner decision, 16 Oct 2026).
 *
 * Until now the row held only the key's HMAC and its last four characters,
 * and the plaintext was shown exactly once, at issuance. In practice that
 * meant a key not written down at that moment was gone, and the only way to
 * get a till licensed was a renewal with `rotate_key` — three of which this
 * platform's first customer accumulated in one afternoon. The HMAC stays what
 * activation checks against; this column is read by one audited Super Admin
 * endpoint and nothing else, and the model never serialises it.
 *
 * Nullable, additive: every licence issued before this reads null, and the
 * page says so rather than pretending.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            if (! Schema::hasColumn('pos_licences', 'key_encrypted')) {
                $table->text('key_encrypted')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('pos_licences', function (Blueprint $table) {
            if (Schema::hasColumn('pos_licences', 'key_encrypted')) {
                $table->dropColumn('key_encrypted');
            }
        });
    }
};
