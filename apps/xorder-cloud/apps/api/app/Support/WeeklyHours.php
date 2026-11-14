<?php

namespace App\Support;

use Carbon\CarbonInterface;

/**
 * Evaluates the per-weekday schedule shape the dashboard's hours editor emits:
 *
 *   ['sat' => ['closed' => false, 'always' => false, 'open' => '07:00', 'close' => '11:00'], …]
 *
 * The same shape already backs restaurant and branch working hours; this is the
 * first place it has to answer "…and is that now?" rather than just be printed.
 */
final class WeeklyHours
{
    /** Saturday-first, matching the editor and the Arabic week. */
    public const DAYS = ['sat', 'sun', 'mon', 'tue', 'wed', 'thu', 'fri'];

    /**
     * Is the schedule open at this moment?
     *
     * An empty schedule means "no restriction" — that is what every record
     * without hours has, so the absence of a schedule can never close anything.
     *
     * @param  array<string,mixed>|null  $schedule
     */
    public static function isOpenAt(?array $schedule, CarbonInterface $now): bool
    {
        if (empty($schedule)) {
            return true;
        }

        $minutes = $now->hour * 60 + $now->minute;

        // A window that runs past midnight (22:00–02:00) belongs to the day it
        // started on, so 01:00 Saturday has to be answered by Friday's entry.
        // Checking both days is what makes the small hours work at all.
        return self::covers($schedule[self::dayKey($now)] ?? null, $minutes, spillover: false)
            || self::covers($schedule[self::dayKey($now->copy()->subDay())] ?? null, $minutes, spillover: true);
    }

    /**
     * The window in force on a given day, as ['open' => '07:00', 'close' => '11:00'],
     * or null when that day is unrestricted (no entry, or open around the clock)
     * or closed outright. Used to tell a diner when the section comes back.
     *
     * @param  array<string,mixed>|null  $schedule
     * @return array{open: string, close: string}|null
     */
    public static function windowOn(?array $schedule, CarbonInterface $day): ?array
    {
        $entry = $schedule[self::dayKey($day)] ?? null;

        if (! is_array($entry) || ! empty($entry['closed']) || ! empty($entry['always'])) {
            return null;
        }

        $open = self::toMinutes($entry['open'] ?? null);
        $close = self::toMinutes($entry['close'] ?? null);

        return $open === null || $close === null
            ? null
            : ['open' => $entry['open'], 'close' => $entry['close']];
    }

    /** Weekday key for a moment, in whatever timezone it already carries. */
    public static function dayKey(CarbonInterface $moment): string
    {
        // Carbon's dayOfWeek is 0=Sunday; DAYS is Saturday-first.
        return ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'][$moment->dayOfWeek];
    }

    /**
     * Does one day's entry cover $minutes past midnight?
     *
     * `$spillover` asks the other question: not "is this day's window open now"
     * but "did this day's window run past midnight into now". Only the tail of
     * an overnight window can answer that one, which is why an unset or
     * round-the-clock day returns false for it — those are already true for the
     * day they belong to, and counting them twice would let a closed day
     * inherit the previous day's openness.
     *
     * @param  array<string,mixed>|null  $entry
     */
    private static function covers(?array $entry, int $minutes, bool $spillover): bool
    {
        if ($entry === null) {
            return ! $spillover;  // an unconfigured day is unrestricted
        }
        if (! empty($entry['closed'])) {
            return false;
        }
        if (! empty($entry['always'])) {
            return ! $spillover;
        }

        $open = self::toMinutes($entry['open'] ?? null);
        $close = self::toMinutes($entry['close'] ?? null);

        if ($open === null || $close === null) {
            return ! $spillover;  // half-filled day: treat as unrestricted
        }

        // close <= open means the window crosses midnight.
        if ($close > $open) {
            return $spillover ? false : ($minutes >= $open && $minutes < $close);
        }

        return $spillover ? $minutes < $close : $minutes >= $open;
    }

    /** "07:30" → 450. Null for anything that is not a well-formed time. */
    private static function toMinutes(mixed $time): ?int
    {
        if (! is_string($time) || ! preg_match('/^(\d{1,2}):(\d{2})$/', $time, $m)) {
            return null;
        }

        $hours = (int) $m[1];
        $minutes = (int) $m[2];

        return $hours > 23 || $minutes > 59 ? null : $hours * 60 + $minutes;
    }
}
