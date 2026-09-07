<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * POS-BE-024 / POS-BE-025 / POS-BE-013 tenant-level columns. All additive.
     *
     * pos_config_version — ONE monotonically increasing integer per tenant,
     * bumped by every bundle-changing write through PosConfigVersion::bump().
     * It is the client's sole precedence signal (accept iff incoming > cached),
     * so it must never be reused or reset. Default 1: every existing tenant
     * starts versioned without a backfill.
     *
     * pos_invoice_config — POS-BE-008's per-tenant sequence settings
     * {prefix_source, padding, reset}. Null = the documented defaults
     * (branch_code / 6 / yearly); delivered read-only in the bootstrap bundle.
     *
     * users.pos_pin_salt / pos_pin_hash — POS-BE-024 as amended 2026-09-02:
     * PBKDF2-HMAC-SHA256, 120000 iterations, 16-byte salt, 32-byte key, both
     * stored base64 (the client ships a tested PBKDF2 verifier; bcrypt would
     * add a Flutter dependency for no gain at a 4-6 digit keyspace). Fresh
     * random salt per set. Deliberately NOT in $fillable (set only via
     * forceFill in the PIN controller, the users.role discipline) and never
     * serialised by UserResource; they appear on exactly one wire — the
     * bootstrap staff[] pin block, behind the device credential.
     */
    public function up(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->unsignedBigInteger('pos_config_version')->default(1);
            $table->string('tax_registration_number', 64)->nullable();
            $table->json('pos_invoice_config')->nullable();
        });

        Schema::table('users', function (Blueprint $table) {
            $table->string('pos_pin_salt', 32)->nullable();
            $table->string('pos_pin_hash', 64)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('restaurants', function (Blueprint $table) {
            $table->dropColumn(['pos_config_version', 'tax_registration_number', 'pos_invoice_config']);
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['pos_pin_salt', 'pos_pin_hash']);
        });
    }
};
