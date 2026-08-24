<?php

namespace Tests\Feature;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

/** `activity:prune` enforces the retention window by date, not by file count. */
class PruneActivityLogsTest extends TestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-08-22 04:00:00');

        $this->dir = storage_path('framework/testing/prune-'.uniqid());
        File::ensureDirectoryExists($this->dir);

        config([
            'logging.channels.activity.path' => $this->dir.'/activity.log',
            'logging.channels.activity.days' => 30,
        ]);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function file(string $name): string
    {
        $path = $this->dir.'/'.$name;
        File::put($path, "line\n");

        return $path;
    }

    public function test_it_keeps_the_window_and_deletes_everything_older(): void
    {
        $today = $this->file('activity-2026-08-22.log');
        $oldest_kept = $this->file('activity-2026-07-24.log');  // today - 29
        $first_dropped = $this->file('activity-2026-07-23.log'); // today - 30
        $ancient = $this->file('activity-2026-01-05.log');

        $this->artisan('activity:prune')->assertSuccessful();

        $this->assertFileExists($today);
        $this->assertFileExists($oldest_kept);
        $this->assertFileDoesNotExist($first_dropped);
        $this->assertFileDoesNotExist($ancient);
    }

    public function test_it_leaves_other_files_alone(): void
    {
        $undated = $this->file('activity.log');
        $other = $this->file('laravel-2026-01-05.log');
        $notADate = $this->file('activity-backup.log');

        $this->artisan('activity:prune')->assertSuccessful();

        $this->assertFileExists($undated);
        $this->assertFileExists($other);
        $this->assertFileExists($notADate);
    }

    public function test_dry_run_reports_without_deleting(): void
    {
        $old = $this->file('activity-2026-01-05.log');

        $this->artisan('activity:prune --dry-run')->assertSuccessful();

        $this->assertFileExists($old);
    }

    public function test_days_option_overrides_the_channel_window(): void
    {
        $kept = $this->file('activity-2026-08-16.log'); // today - 6
        $dropped = $this->file('activity-2026-08-15.log'); // today - 7

        $this->artisan('activity:prune --days=7')->assertSuccessful();

        $this->assertFileExists($kept);
        $this->assertFileDoesNotExist($dropped);
    }
}
