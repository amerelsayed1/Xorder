<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/**
 * The audit trail is mirrored to a per-day file (storage/logs/activity-Y-m-d.log)
 * for tracking/debugging on the box. Tests redirect the channel to a temp dir.
 */
class ActivityLogFileTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->dir = storage_path('framework/testing/activity-'.uniqid());

        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $this->dir.'/activity.log',
        ]);

        Log::forgetChannel('activity');
    }

    protected function tearDown(): void
    {
        Log::forgetChannel('activity');
        File::deleteDirectory($this->dir);

        parent::tearDown();
    }

    /** Today's file is named for the date, so each day gets its own. */
    private function todaysFile(): string
    {
        return $this->dir.'/activity-'.now()->format('Y-m-d').'.log';
    }

    public function test_events_are_appended_to_todays_file(): void
    {
        $admin = User::factory()->superAdmin()->create(['username' => 'superadmin', 'name' => 'Super Admin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk();

        $this->assertFileExists($this->todaysFile());

        // A login records more than one event (the last_login_at write too),
        // so pick the line under test rather than assuming a single-line file.
        $event = collect(explode("\n", trim(file_get_contents($this->todaysFile()))))
            ->map(fn ($l) => json_decode($l, true))
            ->firstWhere('action', 'auth.login');

        $this->assertNotNull($event);
        $this->assertSame($admin->id, $event['actor_id']);
        $this->assertSame('Super Admin', $event['actor_name']);
        $this->assertSame('SUPER_ADMIN', $event['actor_role']);
        $this->assertSame('Signed in', $event['description']);
    }

    public function test_change_diffs_ride_along_on_the_same_line(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin)
            ->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();

        $lines = array_values(array_filter(explode("\n", file_get_contents($this->todaysFile()))));
        $line = collect($lines)->first(fn ($l) => str_contains($l, 'restaurant.updated'));

        $this->assertNotNull($line);
        // One self-contained JSON object per line — the reader depends on it.
        $event = json_decode($line, true);
        $this->assertIsArray($event);
        $this->assertSame($restaurant->id, $event['tenant_id']);
        $this->assertSame('Restaurant', $event['subject_type']);
        $this->assertSame($restaurant->id, $event['subject_id']);
        $this->assertSame(
            ['old' => 'ACTIVE', 'new' => 'SUSPENDED'],
            $event['properties']['changes']['status']
        );
    }

    public function test_no_file_is_written_when_the_mirror_is_disabled(): void
    {
        config(['platform.activity_log_file' => false]);

        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk();

        $this->assertFileDoesNotExist($this->todaysFile());
    }
}
