<?php

namespace App\Console\Commands;

use Carbon\CarbonImmutable;
use Illuminate\Console\Command;

/**
 * Deletes daily activity files (storage/logs/activity-Y-m-d.log) older than the
 * retention window.
 *
 * Monolog's own rotation keeps the N most recent *files*, which drifts from the
 * intent whenever the app is idle for a day (30 files can span far more than 30
 * calendar days). This sweep is date-based instead, so "keep the last 30 days"
 * stays literally true, and it also clears files left behind by an older path
 * or a period when rotation never fired.
 */
class PruneActivityLogs extends Command
{
    protected $signature = 'activity:prune
                            {--days= : Retention window in days (defaults to the channel config)}
                            {--dry-run : List what would be deleted without deleting it}';

    protected $description = 'Delete daily activity log files older than the retention window';

    public function handle(): int
    {
        $days = (int) ($this->option('days') ?? config('logging.channels.activity.days', 30));

        if ($days < 1) {
            $this->error('Retention must be at least 1 day.');

            return self::FAILURE;
        }

        $path = config('logging.channels.activity.path', storage_path('logs/activity.log'));
        $dir = dirname($path);
        $base = pathinfo($path, PATHINFO_FILENAME);
        $ext = pathinfo($path, PATHINFO_EXTENSION);

        // Today counts as one of the retained days, matching the channel's
        // `days` setting: days=30 keeps today plus the previous 29.
        $cutoff = CarbonImmutable::today()->subDays($days - 1);
        $pattern = '/^'.preg_quote($base, '/').'-(\d{4}-\d{2}-\d{2})'.($ext ? '\.'.preg_quote($ext, '/') : '').'$/';

        $deleted = 0;

        foreach (glob($dir.'/'.$base.'-*'.($ext ? '.'.$ext : '')) ?: [] as $file) {
            if (! preg_match($pattern, basename($file), $m)) {
                continue; // not a dated activity file — leave it alone
            }

            // A malformed date must never be read as "very old"; skip it.
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $m[1]);
            if (! $date || $date->format('Y-m-d') !== $m[1] || $date >= $cutoff) {
                continue;
            }

            $this->line(($this->option('dry-run') ? '  would delete ' : '  deleted ').basename($file));

            if (! $this->option('dry-run')) {
                @unlink($file);
            }

            $deleted++;
        }

        $this->info(sprintf(
            '%d activity file(s) older than %s %s (keeping %d days).',
            $deleted,
            $cutoff->format('Y-m-d'),
            $this->option('dry-run') ? 'found' : 'removed',
            $days
        ));

        return self::SUCCESS;
    }
}
