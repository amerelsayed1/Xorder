<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

/** `activity:backfill` moves pre-switch audit_logs history into the daily files. */
class BackfillActivityLogsTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-08-23 10:00:00');

        $this->dir = storage_path('framework/testing/backfill-'.uniqid());
        File::ensureDirectoryExists($this->dir);

        config(['logging.channels.activity.path' => $this->dir.'/activity.log']);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function legacyRow(string $at, string $action = 'auth.login'): AuditLog
    {
        $log = AuditLog::create([
            'action' => $action,
            'actor_name' => 'Old Admin',
            'actor_role' => 'SUPER_ADMIN',
            'description' => 'Signed in',
        ]);
        $log->forceFill(['created_at' => $at])->save();

        return $log;
    }

    private function file(string $date): string
    {
        return $this->dir.'/activity-'.$date.'.log';
    }

    public function test_it_writes_one_file_per_day_in_the_reader_format(): void
    {
        $this->legacyRow('2026-08-01 09:00:00');
        $this->legacyRow('2026-08-01 11:00:00', 'restaurant.updated');
        $this->legacyRow('2026-08-02 09:00:00');

        $this->artisan('activity:backfill')->assertSuccessful();

        $this->assertFileExists($this->file('2026-08-01'));
        $this->assertFileExists($this->file('2026-08-02'));

        $lines = array_values(array_filter(explode("\n", file_get_contents($this->file('2026-08-01')))));
        $this->assertCount(2, $lines);

        $event = json_decode($lines[0], true);
        $this->assertSame('auth.login', $event['action']);
        $this->assertSame('Old Admin', $event['actor_name']);
        $this->assertStringStartsWith('2026-08-01', $event['ts']);
    }

    public function test_it_skips_days_already_written_live(): void
    {
        $this->legacyRow('2026-08-01 09:00:00');
        File::put($this->file('2026-08-01'), "{\"action\":\"live\"}\n");

        $this->artisan('activity:backfill')->assertSuccessful();

        // Untouched — re-exporting would duplicate every line of that day.
        $this->assertSame("{\"action\":\"live\"}\n", file_get_contents($this->file('2026-08-01')));
    }

    public function test_force_rewrites_an_existing_day(): void
    {
        $this->legacyRow('2026-08-01 09:00:00');
        File::put($this->file('2026-08-01'), "stale\n");

        $this->artisan('activity:backfill --force')->assertSuccessful();

        $this->assertStringContainsString('auth.login', file_get_contents($this->file('2026-08-01')));
    }

    public function test_dry_run_writes_nothing(): void
    {
        $this->legacyRow('2026-08-01 09:00:00');

        $this->artisan('activity:backfill --dry-run')->assertSuccessful();

        $this->assertFileDoesNotExist($this->file('2026-08-01'));
    }

    /**
     * The command runs as root in production while php-fpm writes as www-data;
     * a file it cannot append to stops the trail dead.
     */
    public function test_written_files_stay_writable_by_the_web_user(): void
    {
        $this->legacyRow('2026-08-01 09:00:00');

        $this->artisan('activity:backfill')->assertSuccessful();

        $mode = fileperms($this->file('2026-08-01')) & 0777;
        $this->assertSame(0664, $mode, 'backfilled files must stay group-writable');
        $this->assertSame(fileowner($this->dir), fileowner($this->file('2026-08-01')));
    }

    public function test_an_empty_table_is_not_an_error(): void
    {
        $this->artisan('activity:backfill')->assertSuccessful();
    }
}
