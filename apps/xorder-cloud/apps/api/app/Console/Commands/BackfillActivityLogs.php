<?php

namespace App\Console\Commands;

use App\Models\AuditLog;
use App\Services\ActivityLogReader;
use Illuminate\Console\Command;

/**
 * Exports the legacy `audit_logs` table into the daily activity files.
 *
 * The files became the system of record part-way through the product's life, so
 * without this the audit screen would start at the day file logging was
 * switched on and every earlier event would vanish from the UI — still in the
 * table, but nothing reads it any more. One run migrates that history into the
 * format {@see ActivityLogReader} serves.
 *
 * Days that already have a file are skipped: they were written live and
 * re-exporting them would duplicate every line.
 */
class BackfillActivityLogs extends Command
{
    protected $signature = 'activity:backfill
                            {--force : Also rewrite days that already have a file}
                            {--dry-run : Report what would be written without writing it}';

    protected $description = 'Export legacy audit_logs rows into the daily activity files';

    public function handle(): int
    {
        $path = config('logging.channels.activity.path', storage_path('logs/activity.log'));
        $dir = dirname($path);
        $base = pathinfo($path, PATHINFO_FILENAME);
        $ext = pathinfo($path, PATHINFO_EXTENSION);

        if (! is_dir($dir) && ! @mkdir($dir, 0775, true) && ! is_dir($dir)) {
            $this->error("Cannot create {$dir}.");

            return self::FAILURE;
        }

        // Group in memory by day, then write each file once: appending per row
        // would reopen the same handle thousands of times.
        $byDate = [];
        $total = 0;

        AuditLog::query()->orderBy('created_at')->orderBy('id')->chunk(1000, function ($rows) use (&$byDate, &$total) {
            foreach ($rows as $row) {
                $byDate[$row->created_at->format('Y-m-d')][] = $this->encode($row);
                $total++;
            }
        });

        if ($total === 0) {
            $this->info('Nothing to backfill — audit_logs is empty.');

            return self::SUCCESS;
        }

        ksort($byDate);
        $written = 0;
        $skipped = 0;

        foreach ($byDate as $date => $lines) {
            $file = $dir.'/'.$base.'-'.$date.($ext ? '.'.$ext : '');

            if (file_exists($file) && ! $this->option('force')) {
                $this->line(sprintf('  skipped %s (%d row(s)) — file already exists', $date, count($lines)));
                $skipped += count($lines);

                continue;
            }

            $this->line(sprintf('  %s %s (%d row(s))', $this->option('dry-run') ? 'would write' : 'wrote', $date, count($lines)));

            if (! $this->option('dry-run')) {
                file_put_contents($file, implode("\n", $lines)."\n");
                $this->handOverToTheWebUser($file, $dir);
            }

            $written += count($lines);
        }

        $this->info(sprintf(
            '%d row(s) %s across %d day file(s); %d skipped (day already logged live).',
            $written,
            $this->option('dry-run') ? 'would be exported' : 'exported',
            count($byDate),
            $skipped
        ));

        return self::SUCCESS;
    }

    /**
     * Give the file back to whoever owns the log directory.
     *
     * This command is normally run as root (`docker exec app php artisan …`)
     * while the app writes as www-data. Without this, the backfill leaves
     * root-owned files that php-fpm cannot append to, and every subsequent
     * event is dropped with "Permission denied" — the trail silently stops.
     */
    private function handOverToTheWebUser(string $file, string $dir): void
    {
        @chmod($file, 0664);

        if (($owner = @fileowner($dir)) !== false) {
            @chown($file, $owner);
        }

        if (($group = @filegroup($dir)) !== false) {
            @chgrp($file, $group);
        }
    }

    /** One table row in the exact on-disk shape AuditLogger writes. */
    private function encode(AuditLog $row): string
    {
        $line = json_encode([
            'ts' => $row->created_at->toIso8601String(),
            'action' => $row->action,
            'tenant_id' => $row->restaurant_id,
            'actor_id' => $row->actor_id,
            'actor_name' => $row->actor_name,
            'actor_role' => $row->actor_role,
            'subject_type' => $row->auditable_type ? class_basename($row->auditable_type) : null,
            'subject_id' => $row->auditable_id,
            'ip' => $row->ip_address,
            'description' => $row->description,
            'properties' => $row->properties ?: null,
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

        return str_replace(["\r", "\n"], ' ', (string) $line);
    }
}
