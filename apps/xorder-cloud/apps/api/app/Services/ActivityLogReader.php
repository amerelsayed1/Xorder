<?php

namespace App\Services;

use App\Models\Restaurant;
use Carbon\CarbonImmutable;
use Illuminate\Support\Str;

/**
 * Reads the daily activity files (storage/logs/activity-Y-m-d.log) back for the
 * audit screens. The files are the system of record — there is no table to
 * query — so this has to filter, count and paginate over plain text.
 *
 * The trick that makes that affordable: {@see AuditLogger} writes each event as
 * one JSON object with a FIXED key order, so a filter can be answered by
 * matching a substring (`"tenant_id":7,`) against the raw line. Counting a
 * month of history therefore costs a scan, not a million json_decode() calls —
 * only the ~30 lines of the requested page are ever decoded.
 *
 * Ordering is newest-first: files are walked newest to oldest, and lines within
 * a file are appended chronologically, so each file is read back to front.
 */
class ActivityLogReader
{
    /**
     * One page of events, shaped exactly like the old AuditLogResource
     * collection so the SPA sees no difference.
     *
     * @param  array<string,mixed>  $filters
     * @return array{data: list<array<string,mixed>>, meta: array<string,int>}
     */
    public function paginate(array $filters, int $page = 1, int $perPage = 30): array
    {
        $page = max(1, $page);
        $perPage = max(1, $perPage);
        $needles = $this->needles($filters);

        $offset = ($page - 1) * $perPage;
        $total = 0;
        $rows = [];

        foreach ($this->files($filters) as $date => $path) {
            $matched = $this->matchingLines($path, $needles);
            $count = count($matched);
            $total += $count;

            // Walk every file even once the page is full: `total` (and so the
            // pager's last_page) is only correct if all matches are counted.
            if (count($rows) >= $perPage) {
                continue;
            }

            // Newest first within the day.
            $matched = array_reverse($matched, true);

            $skip = max(0, $offset - ($total - $count));
            if ($skip >= $count) {
                continue;
            }

            foreach (array_slice($matched, $skip, $perPage - count($rows), true) as $lineNo => $line) {
                $row = $this->decode($line, $date, $lineNo);
                if ($row !== null) {
                    $rows[] = $row;
                }
            }
        }

        return [
            'data' => $rows,
            'meta' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => max(1, (int) ceil($total / $perPage)),
            ],
        ];
    }

    /**
     * Distinct actors, actions and categories present in the retained files —
     * the filter dropdowns. Scraped with regexes rather than decoded, for the
     * same reason the page path avoids decoding.
     *
     * @return array{actors: list<array<string,mixed>>, actions: list<string>, categories: list<string>}
     */
    public function options(): array
    {
        $actors = [];
        $actions = [];

        foreach ($this->files([]) as $path) {
            foreach ($this->lines($path) as $line) {
                if (preg_match('/"action":"([^"]+)"/', $line, $m)) {
                    $actions[$m[1]] = true;
                }

                if (preg_match('/"actor_id":(\d+),"actor_name":(null|"(?:[^"\\\\]|\\\\.)*"),"actor_role":(null|"[^"]*")/', $line, $m)) {
                    $actors[$m[1]] ??= [
                        'id' => (int) $m[1],
                        'name' => $m[2] === 'null' ? null : json_decode($m[2]),
                        'role' => $m[3] === 'null' ? null : trim($m[3], '"'),
                    ];
                }
            }
        }

        ksort($actions);
        $actions = array_keys($actions);

        $categories = array_values(array_unique(array_map(
            fn (string $a) => str_contains($a, '.') ? strtok($a, '.') : $a,
            $actions
        )));

        usort($actors, fn ($a, $b) => strcmp((string) $a['name'], (string) $b['name']));

        return [
            'actors' => array_values($actors),
            'actions' => $actions,
            'categories' => $categories,
        ];
    }

    /**
     * The day files themselves — what exists on disk, newest first. The trail
     * is a pile of files now, so the screen can show it as one.
     *
     * Filters (currently restaurant_id) scope the event count: on a tenant's
     * page "312 events" must mean 312 of *theirs*, not 312 platform-wide.
     * `bytes` is always the real file size — it describes the file, not the
     * slice, and a download of the filtered slice states its own size.
     *
     * @param  array<string,mixed>  $filters
     * @return list<array{date: string, filename: string, bytes: int, events: int}>
     */
    public function inventory(array $filters = []): array
    {
        $needles = $this->needles($filters);
        $out = [];

        foreach ($this->files($filters) as $date => $path) {
            $out[] = [
                'date' => $date,
                'filename' => basename($path),
                'bytes' => (int) @filesize($path),
                'events' => count($this->matchingLines($path, $needles)),
            ];
        }

        return $out;
    }

    /**
     * One day's raw lines, optionally narrowed by the same filters the feed
     * uses — so a download taken from a tenant's page carries that tenant's
     * events rather than every tenant that happened to share the day.
     *
     * @param  array<string,mixed>  $filters
     */
    public function rawLinesFor(string $date, array $filters = []): ?string
    {
        $path = $this->files([])[$date] ?? null;

        if ($path === null) {
            return null;
        }

        $lines = $this->matchingLines($path, $this->needles($filters));

        return $lines === [] ? '' : implode("\n", $lines)."\n";
    }

    /**
     * Absolute path of one day's file, or null if that day has no file (or the
     * caller made the date up — this is the only place a request-supplied value
     * reaches the filesystem, so it is matched against the known set rather
     * than concatenated into a path).
     */
    public function pathForDate(string $date): ?string
    {
        return $this->files([])[$date] ?? null;
    }

    /**
     * Retained day files, newest first, keyed by date. `from`/`to` are applied
     * here: the day is in the filename, so a date range never opens a file it
     * does not need.
     *
     * @param  array<string,mixed>  $filters
     * @return array<string,string>
     */
    private function files(array $filters): array
    {
        $path = config('logging.channels.activity.path', storage_path('logs/activity.log'));
        $dir = dirname($path);
        $base = pathinfo($path, PATHINFO_FILENAME);
        $ext = pathinfo($path, PATHINFO_EXTENSION);

        $from = $this->date($filters['from'] ?? null);
        $to = $this->date($filters['to'] ?? null);

        $found = [];

        foreach (glob($dir.'/'.$base.'-*'.($ext ? '.'.$ext : '')) ?: [] as $file) {
            if (! preg_match('/-(\d{4}-\d{2}-\d{2})'.($ext ? '\.'.preg_quote($ext, '/') : '').'$/', $file, $m)) {
                continue;
            }

            $date = $m[1];

            if (($from && $date < $from->format('Y-m-d')) || ($to && $date > $to->format('Y-m-d'))) {
                continue;
            }

            $found[$date] = $file;
        }

        krsort($found);

        return $found;
    }

    /**
     * Substrings every matching line must contain. Built from the fixed key
     * order the writer guarantees; the trailing comma is what stops
     * `"tenant_id":7,` from also matching tenant 70.
     *
     * @param  array<string,mixed>  $filters
     * @return array{all: list<string>, search: ?string}
     */
    private function needles(array $filters): array
    {
        $all = [];

        if (($id = $filters['restaurant_id'] ?? null) !== null && $id !== '') {
            $all[] = '"tenant_id":'.(int) $id.',';
        }

        if (($id = $filters['actor_id'] ?? null) !== null && $id !== '') {
            $all[] = '"actor_id":'.(int) $id.',';
        }

        if ($role = $filters['actor_role'] ?? null) {
            $all[] = '"actor_role":"'.$role.'",';
        }

        if ($action = $filters['action'] ?? null) {
            $all[] = '"action":"'.$action.'",';
        }

        if ($category = $filters['category'] ?? null) {
            $all[] = '"action":"'.$category.'.';
        }

        $search = ($s = $filters['search'] ?? null) ? (string) $s : null;

        return ['all' => $all, 'search' => $search];
    }

    /**
     * Raw matching lines of one file, keyed by line number.
     *
     * @param  array{all: list<string>, search: ?string}  $needles
     * @return array<int,string>
     */
    private function matchingLines(string $path, array $needles): array
    {
        $matched = [];

        foreach ($this->lines($path) as $lineNo => $line) {
            // Only JSON objects are events. Anything else — a stray line, a
            // hand-edit, a file left over from an older format — is skipped
            // here rather than at decode time, so it can never be counted
            // towards a total it will not appear in.
            if (! str_starts_with($line, '{')) {
                continue;
            }

            foreach ($needles['all'] as $needle) {
                if (! str_contains($line, $needle)) {
                    continue 2;
                }
            }

            // Free-text runs over the whole line rather than the description
            // alone — searching for an IP or an action key should work too.
            if ($needles['search'] !== null && ! Str::contains($line, $needles['search'], ignoreCase: true)) {
                continue;
            }

            $matched[$lineNo] = $line;
        }

        return $matched;
    }

    /**
     * Stream a file line by line — these can be large, and nothing here needs
     * more than one line in memory at a time.
     *
     * @return \Generator<int,string>
     */
    private function lines(string $path): \Generator
    {
        $handle = @fopen($path, 'rb');

        if ($handle === false) {
            return;
        }

        try {
            $lineNo = 0;
            while (($line = fgets($handle)) !== false) {
                $line = rtrim($line, "\r\n");
                if ($line !== '') {
                    yield $lineNo++ => $line;
                }
            }
        } finally {
            fclose($handle);
        }
    }

    /**
     * One raw line into the row shape the SPA already renders.
     *
     * @return array<string,mixed>|null
     */
    private function decode(string $line, string $date, int $lineNo): ?array
    {
        $e = json_decode($line, true);

        if (! is_array($e)) {
            return null; // a truncated or hand-edited line must not break the page
        }

        $action = (string) ($e['action'] ?? '');

        return [
            // No autoincrement to borrow, but the SPA only needs a stable key.
            'id' => $date.':'.$lineNo,
            'action' => $action,
            'category' => str_contains($action, '.') ? strtok($action, '.') : $action,
            'description' => $e['description'] ?? null,
            'actor' => [
                'id' => $e['actor_id'] ?? null,
                'name' => $e['actor_name'] ?? null,
                'role' => $e['actor_role'] ?? null,
            ],
            'tenant' => isset($e['tenant_id']) && $e['tenant_id'] !== null
                ? ['id' => $e['tenant_id'], 'name' => $this->tenantName((int) $e['tenant_id'])]
                : null,
            'subject' => isset($e['subject_type']) && $e['subject_type'] !== null
                ? ['type' => $e['subject_type'], 'id' => $e['subject_id'] ?? null]
                : null,
            'properties' => $e['properties'] ?? null,
            'ip_address' => $e['ip'] ?? null,
            'created_at' => $e['ts'] ?? null,
        ];
    }

    /** @var array<int,string>|null */
    private ?array $tenantNames = null;

    /**
     * Tenant names are the one thing the file cannot carry — a restaurant can
     * be renamed after the fact, and the screen should show what it is called
     * now. Loaded once per request, not per row.
     */
    private function tenantName(int $id): ?string
    {
        $this->tenantNames ??= Restaurant::query()
            ->withoutGlobalScopes()
            ->pluck('name_en', 'id')
            ->map(fn ($n) => $n ?: null)
            ->all();

        return $this->tenantNames[$id] ?? null;
    }

    private function date(mixed $value): ?CarbonImmutable
    {
        if (! $value) {
            return null;
        }

        try {
            return CarbonImmutable::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }
}
