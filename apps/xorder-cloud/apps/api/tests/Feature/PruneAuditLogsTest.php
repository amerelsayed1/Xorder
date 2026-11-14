<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/** `audit:prune` trims audit_logs to the retention window. */
class PruneAuditLogsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-08-22 04:00:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function logAt(string $date, string $action = 'order.updated'): AuditLog
    {
        $log = AuditLog::create(['action' => $action, 'description' => $date]);
        $log->forceFill(['created_at' => $date])->save();

        return $log->refresh();
    }

    public function test_it_keeps_the_window_and_deletes_everything_older(): void
    {
        $today = $this->logAt('2026-08-22 09:00:00');
        // 90 days of history ending today => the window opens on 2026-05-25.
        $oldestKept = $this->logAt('2026-05-25 00:00:00');
        $firstDropped = $this->logAt('2026-05-24 23:59:59');
        $ancient = $this->logAt('2025-01-05 12:00:00');

        $this->artisan('audit:prune')->assertSuccessful();

        $this->assertModelExists($today);
        $this->assertModelExists($oldestKept);
        $this->assertModelMissing($firstDropped);
        $this->assertModelMissing($ancient);
    }

    public function test_it_deletes_across_chunk_boundaries(): void
    {
        foreach (range(1, 7) as $i) {
            $this->logAt('2025-01-0'.$i.' 12:00:00');
        }
        $recent = $this->logAt('2026-08-20 12:00:00');

        $this->artisan('audit:prune --chunk=2')->assertSuccessful();

        $this->assertSame(1, AuditLog::count());
        $this->assertModelExists($recent);
    }

    public function test_dry_run_reports_without_deleting(): void
    {
        $old = $this->logAt('2025-01-05 12:00:00');

        $this->artisan('audit:prune --dry-run')->assertSuccessful();

        $this->assertModelExists($old);
    }

    public function test_zero_retention_disables_pruning(): void
    {
        config(['platform.audit_log_days' => 0]);
        $old = $this->logAt('2020-01-05 12:00:00');

        $this->artisan('audit:prune')->assertSuccessful();

        $this->assertModelExists($old);
    }
}
