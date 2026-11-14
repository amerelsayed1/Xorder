<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

/**
 * Scrub credential values out of the daily activity files already written.
 *
 * Until 16 Oct 2026 the change diff on an "updated" event recorded every
 * column not in a short exclusion list — which put the cashier PIN's salt and
 * hash, and a terminal's device-token hash and fingerprint, into
 * `storage/logs/activity-*.log` for anyone with audit.view to read. The diff
 * no longer records them (see Auditable::auditExcludedAttributes); this
 * rewrites what was recorded before, in place, leaving every other field of
 * every line exactly as it was. Idempotent: a redacted line stays redacted.
 */
class RedactActivitySecrets extends Command
{
    protected $signature = 'activity:redact-secrets
                            {--dry-run : Count what would change without writing}';

    protected $description = 'Replace credential values in existing activity log files with [redacted]';

    /** Keys whose old/new values must never sit in a log line. */
    public const SECRET_KEYS = [
        'password', 'remember_token',
        'pos_pin_salt', 'pos_pin_hash',
        'device_token_hash', 'previous_token_hash', 'register_response_cache', 'fingerprint',
    ];

    public const REDACTED = '[redacted]';

    public function handle(): int
    {
        $path = config('logging.channels.activity.path', storage_path('logs/activity.log'));
        $dir = dirname($path);
        $base = pathinfo($path, PATHINFO_FILENAME);
        $ext = pathinfo($path, PATHINFO_EXTENSION);

        $files = glob($dir.'/'.$base.'-*'.($ext ? '.'.$ext : '')) ?: [];
        $linesChanged = 0;
        $filesChanged = 0;

        foreach ($files as $file) {
            $lines = file($file, FILE_IGNORE_NEW_LINES);
            if ($lines === false) {
                continue;
            }
            $changed = false;
            foreach ($lines as $i => $line) {
                $redacted = self::redactLine($line);
                if ($redacted !== $line) {
                    $lines[$i] = $redacted;
                    $changed = true;
                    $linesChanged++;
                }
            }
            if ($changed) {
                $filesChanged++;
                if (! $this->option('dry-run')) {
                    file_put_contents($file, implode("\n", $lines)."\n", LOCK_EX);
                }
            }
        }

        $this->info(sprintf(
            '%s %d line(s) in %d file(s).',
            $this->option('dry-run') ? 'Would redact' : 'Redacted',
            $linesChanged,
            $filesChanged,
        ));

        return self::SUCCESS;
    }

    /**
     * One JSON line, with any secret key under `properties.changes` (or at the
     * top of `properties`) replaced. A line that is not JSON, or carries none,
     * comes back unchanged — byte for byte, so untouched days stay untouched.
     */
    public static function redactLine(string $line): string
    {
        if ($line === '' || ! str_contains($line, 'properties')) {
            return $line;
        }
        $event = json_decode($line, true);
        if (! is_array($event) || ! is_array($event['properties'] ?? null)) {
            return $line;
        }

        $touched = false;
        $properties = $event['properties'];

        foreach (['changes', 'attributes'] as $bag) {
            if (is_array($properties[$bag] ?? null)) {
                foreach ($properties[$bag] as $key => $value) {
                    if (in_array($key, self::SECRET_KEYS, true)) {
                        $properties[$bag][$key] = is_array($value) && array_key_exists('new', $value)
                            ? ['old' => self::REDACTED, 'new' => self::REDACTED]
                            : self::REDACTED;
                        $touched = true;
                    }
                }
            }
        }
        foreach ($properties as $key => $value) {
            if (in_array($key, self::SECRET_KEYS, true) && $value !== self::REDACTED) {
                $properties[$key] = self::REDACTED;
                $touched = true;
            }
        }

        if (! $touched) {
            return $line;
        }
        $event['properties'] = $properties;

        return json_encode($event, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }
}
