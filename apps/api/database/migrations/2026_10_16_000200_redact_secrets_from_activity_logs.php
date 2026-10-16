<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Log;

/**
 * One-off, run by the deploy like any migration: scrub the cashier PIN salts
 * and hashes, and terminal token hashes, that the change-diff audit wrote
 * into the daily activity files before 16 Oct 2026. The diff no longer records
 * them; this takes care of what was already on disk. Idempotent, and never
 * the reason a deploy fails — a log file that cannot be rewritten is logged
 * and left for `php artisan activity:redact-secrets` by hand.
 */
return new class extends Migration
{
    public function up(): void
    {
        try {
            Artisan::call('activity:redact-secrets');
        } catch (Throwable $e) {
            Log::warning('activity:redact-secrets did not complete during migration: '.$e->getMessage());
        }
    }

    public function down(): void
    {
        // Redaction is not reversible, by design.
    }
};
