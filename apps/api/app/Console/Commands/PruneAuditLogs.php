<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use Carbon\CarbonImmutable;
use Illuminate\Console\Command;

/**
 * Trims the audit_logs table to the retention window.
 *
 * Orders are audited, so this table grows with every order and every status
 * transition — left alone it becomes the largest table in the schema and slows
 * the Super Admin audit screen it exists to serve. Rows are deleted in chunks
 * by id: one unbounded `DELETE` over months of history would hold locks long
 * enough to stall live order writes.
 */
class PruneAuditLogs extends Command
{
    protected $signature = 'audit:prune
                            {--days= : Retention window in days (defaults to platform.audit_log_days)}
                            {--chunk=1000 : Rows deleted per statement}
                            {--dry-run : Report what would be deleted without deleting it}';

    protected $description = 'Delete audit_logs rows older than the retention window';

    public function handle(): int
    {
        $days = (int) ($this->option('days') ?? config('platform.audit_log_days', 90));

        if ($days < 1) {
            $this->info('Audit log pruning is disabled (retention is 0 days or less).');

            return self::SUCCESS;
        }

        $chunk = max(1, (int) $this->option('chunk'));

        // Today counts as one of the retained days, matching activity:prune.
        $cutoff = CarbonImmutable::today()->subDays($days - 1);

        $stale = AuditLog::query()->where('created_at', '<', $cutoff);

        if ($this->option('dry-run')) {
            $this->info(sprintf(
                '%d audit row(s) predate %s (keeping %d days).',
                $stale->count(),
                $cutoff->format('Y-m-d'),
                $days
            ));

            return self::SUCCESS;
        }

        $deleted = 0;

        // Postgres has no DELETE ... LIMIT, so take the ids first, then delete
        // by key — which also keeps each statement's lock footprint predictable.
        while (true) {
            $ids = AuditLog::query()
                ->where('created_at', '<', $cutoff)
                ->orderBy('id')
                ->limit($chunk)
                ->pluck('id');

            if ($ids->isEmpty()) {
                break;
            }

            $deleted += AuditLog::query()->whereIn('id', $ids)->delete();
        }

        $this->info(sprintf(
            '%d audit row(s) older than %s removed (keeping %d days).',
            $deleted,
            $cutoff->format('Y-m-d'),
            $days
        ));

        return self::SUCCESS;
    }
}
