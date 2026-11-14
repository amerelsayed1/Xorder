<?php

namespace Tests\Unit;

use App\Support\WeeklyHours;
use Carbon\Carbon;
use PHPUnit\Framework\TestCase;

/**
 * The weekday-schedule evaluator behind category serving times.
 *
 * Most of these cases are about the edges: midnight-crossing windows, the day
 * boundary, and the "no schedule at all" state that every existing record has.
 */
class WeeklyHoursTest extends TestCase
{
    /** 2026-08-16 is a Sunday; 2026-08-15 a Saturday. */
    private function at(string $datetime): Carbon
    {
        return Carbon::parse($datetime, 'UTC');
    }

    private function breakfast(): array
    {
        return ['sun' => ['open' => '07:00', 'close' => '11:00']];
    }

    public function test_no_schedule_means_always_open(): void
    {
        $this->assertTrue(WeeklyHours::isOpenAt(null, $this->at('2026-08-16 03:00')));
        $this->assertTrue(WeeklyHours::isOpenAt([], $this->at('2026-08-16 03:00')));
    }

    public function test_inside_the_window_is_open(): void
    {
        $this->assertTrue(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-16 09:30')));
    }

    public function test_the_opening_minute_is_open_and_the_closing_minute_is_not(): void
    {
        // Half-open interval: 11:00–… is the next thing, not still breakfast.
        $this->assertTrue(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-16 07:00')));
        $this->assertFalse(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-16 11:00')));
    }

    public function test_outside_the_window_is_closed(): void
    {
        $this->assertFalse(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-16 06:59')));
        $this->assertFalse(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-16 15:00')));
    }

    public function test_a_day_with_no_entry_is_unrestricted(): void
    {
        // Saturday is absent from the breakfast schedule entirely.
        $this->assertTrue(WeeklyHours::isOpenAt($this->breakfast(), $this->at('2026-08-15 15:00')));
    }

    public function test_a_closed_day_is_closed_all_day(): void
    {
        $schedule = ['sun' => ['closed' => true, 'open' => '07:00', 'close' => '11:00']];

        $this->assertFalse(WeeklyHours::isOpenAt($schedule, $this->at('2026-08-16 09:00')));
        $this->assertFalse(WeeklyHours::isOpenAt($schedule, $this->at('2026-08-16 23:00')));
    }

    public function test_an_always_day_is_open_around_the_clock(): void
    {
        $schedule = ['sun' => ['always' => true]];

        $this->assertTrue(WeeklyHours::isOpenAt($schedule, $this->at('2026-08-16 04:00')));
    }

    public function test_a_half_filled_day_is_treated_as_unrestricted(): void
    {
        // An owner who set an opening time but never a closing one should not
        // have the section silently vanish.
        $schedule = ['sun' => ['open' => '18:00']];

        $this->assertTrue(WeeklyHours::isOpenAt($schedule, $this->at('2026-08-16 09:00')));
    }

    // ── Windows that cross midnight ────────────────────────────────────────

    public function test_an_overnight_window_is_open_before_midnight(): void
    {
        $shisha = ['sun' => ['open' => '18:00', 'close' => '02:00']];

        $this->assertTrue(WeeklyHours::isOpenAt($shisha, $this->at('2026-08-16 23:30')));
    }

    public function test_an_overnight_window_is_open_after_midnight_on_the_next_day(): void
    {
        // 01:00 Monday is still Sunday's 18:00–02:00 window. Monday itself has
        // no entry — the answer has to come from the day before.
        $shisha = ['sun' => ['open' => '18:00', 'close' => '02:00'], 'mon' => ['closed' => true]];

        $this->assertTrue(WeeklyHours::isOpenAt($shisha, $this->at('2026-08-17 01:00')));
        $this->assertFalse(WeeklyHours::isOpenAt($shisha, $this->at('2026-08-17 02:00')));
        $this->assertFalse(WeeklyHours::isOpenAt($shisha, $this->at('2026-08-17 12:00')));
    }

    public function test_an_ordinary_window_does_not_leak_into_the_next_day(): void
    {
        // Saturday 07:00–11:00 must say nothing about Sunday 08:00 — that is
        // Sunday's own business, and Sunday here is shut.
        $schedule = ['sat' => ['open' => '07:00', 'close' => '11:00'], 'sun' => ['closed' => true]];

        $this->assertFalse(WeeklyHours::isOpenAt($schedule, $this->at('2026-08-16 08:00')));
    }

    // ── The window a diner is told about ───────────────────────────────────

    public function test_the_days_window_is_reported_for_display(): void
    {
        $this->assertSame(
            ['open' => '07:00', 'close' => '11:00'],
            WeeklyHours::windowOn($this->breakfast(), $this->at('2026-08-16 15:00'))
        );
    }

    public function test_no_window_is_reported_for_unrestricted_or_closed_days(): void
    {
        $this->assertNull(WeeklyHours::windowOn(null, $this->at('2026-08-16 15:00')));
        $this->assertNull(WeeklyHours::windowOn(['sun' => ['always' => true]], $this->at('2026-08-16 15:00')));
        $this->assertNull(WeeklyHours::windowOn(['sun' => ['closed' => true]], $this->at('2026-08-16 15:00')));
    }

    public function test_day_keys_are_saturday_first(): void
    {
        $this->assertSame('sun', WeeklyHours::dayKey($this->at('2026-08-16 12:00')));
        $this->assertSame('sat', WeeklyHours::dayKey($this->at('2026-08-15 12:00')));
        $this->assertSame('mon', WeeklyHours::dayKey($this->at('2026-08-17 12:00')));
    }
}
