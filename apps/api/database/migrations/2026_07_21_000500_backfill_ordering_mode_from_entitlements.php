<?php

use App\Enums\OrderingMode;
use App\Models\Restaurant;
use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        // ordering_mode was added with a blanket 'both' default; cap each existing
        // restaurant to what its plan entitlements actually grant so the stored
        // mode never claims a channel the plan doesn't include.
        Restaurant::with('features')->get()->each(function (Restaurant $r) {
            $target = $r->effectiveOrderingMode() ?? OrderingMode::WHATSAPP;
            if ($r->ordering_mode !== $target) {
                // updateQuietly: a system backfill must not fire model events.
                // The Auditable `updated` hook would try to write to audit_logs,
                // which this migration predates — on Postgres that failed insert
                // aborts the whole migration transaction.
                $r->updateQuietly(['ordering_mode' => $target->value]);
            }
        });
    }

    public function down(): void
    {
        // No-op: the pre-backfill blanket 'both' cannot be reconstructed.
    }
};
