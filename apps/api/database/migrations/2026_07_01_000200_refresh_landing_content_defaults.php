<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * One-time content refresh: the landing copy was fully rewritten (bilingual
     * SEO, monthly/yearly pricing, WhatsApp-first ordering wording, etc.).
     * Because saved content wins over defaults, clear the singleton row so it
     * regenerates from the current LandingContent::defaultContent() on next
     * access. Idempotent — a no-op once the row is gone.
     */
    public function up(): void
    {
        DB::table('landing_contents')->delete();
    }

    public function down(): void
    {
        // No-op: content regenerates from defaults; nothing to restore.
    }
};
