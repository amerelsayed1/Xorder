<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/**
 * The activity trail end to end: events are recorded into the daily files, and
 * the super-admin endpoint reads and filters them back out. There is no audit
 * table involved — the files are the system of record.
 */
class AuditLogTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->dir = storage_path('framework/testing/audit-'.uniqid());

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

    /** Every event recorded today, decoded. */
    private function events(): array
    {
        $file = $this->dir.'/activity-'.now()->format('Y-m-d').'.log';

        if (! file_exists($file)) {
            return [];
        }

        return array_map(
            fn ($l) => json_decode($l, true),
            array_values(array_filter(explode("\n", file_get_contents($file))))
        );
    }

    private function actions(): array
    {
        return array_column($this->events(), 'action');
    }

    // ------------------------------------------------------------ recording

    public function test_successful_login_is_audited(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk();

        $this->assertContains('auth.login', $this->actions());
    }

    public function test_failed_login_is_audited_without_an_actor(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'nope'])
            ->assertStatus(401);

        $event = collect($this->events())->firstWhere('action', 'auth.login_failed');

        $this->assertNotNull($event);
        $this->assertNull($event['actor_id']);
        $this->assertSame('ANONYMOUS', $event['actor_role']);
    }

    public function test_status_change_is_audited_with_actor_and_tenant(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin)
            ->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();

        $event = collect($this->events())->last(fn ($e) => $e['action'] === 'restaurant.updated');

        $this->assertNotNull($event);
        $this->assertSame($admin->id, $event['actor_id']);
        $this->assertSame($restaurant->id, $event['tenant_id']);
        $this->assertSame('SUSPENDED', $event['properties']['changes']['status']['new']);
    }

    public function test_deleting_a_restaurant_commits_and_is_platform_scoped(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create(['status' => 'ARCHIVED', 'slug' => 'to-delete']);
        $rid = $r->id;

        $this->actingAs($admin)
            ->deleteJson("/api/admin/restaurants/{$rid}", ['confirmation' => 'to-delete'])
            ->assertOk();

        // The delete transaction must actually commit (regression: the audit
        // hook once inserted a dangling restaurant_id FK and rolled it back).
        $this->assertDatabaseMissing('restaurants', ['id' => $rid]);

        $event = collect($this->events())
            ->first(fn ($e) => $e['action'] === 'restaurant.deleted' && $e['subject_id'] === $rid);

        // Scoped to the platform, with the id preserved on the subject.
        $this->assertNotNull($event);
        $this->assertNull($event['tenant_id']);
        $this->assertSame('Restaurant', $event['subject_type']);
    }

    // ------------------------------------------------------------- endpoint

    public function test_index_filters_by_tenant_and_actor(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $a = Restaurant::factory()->create(['status' => 'ACTIVE']);
        $b = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin);
        $this->patchJson("/api/admin/restaurants/{$a->id}/status", ['status' => 'SUSPENDED'])->assertOk();
        $this->patchJson("/api/admin/restaurants/{$b->id}/status", ['status' => 'SUSPENDED'])->assertOk();
        $this->postJson('/api/auth/login', ['username' => 'nobody', 'password' => 'nope'])->assertStatus(401);

        $byTenant = $this->getJson("/api/admin/audit-logs?restaurant_id={$a->id}")->assertOk()->json('data');
        $this->assertNotEmpty($byTenant);
        foreach ($byTenant as $row) {
            $this->assertSame($a->id, $row['tenant']['id']);
        }

        $byActor = $this->getJson("/api/admin/audit-logs?actor_id={$admin->id}&category=restaurant")
            ->assertOk()->json('data');
        $this->assertNotEmpty($byActor);
        foreach ($byActor as $row) {
            $this->assertSame($admin->id, $row['actor']['id']);
            $this->assertSame('restaurant', $row['category']);
        }
    }

    public function test_index_returns_newest_first_with_pager_meta(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin);
        foreach (['SUSPENDED', 'ACTIVE', 'SUSPENDED'] as $status) {
            $this->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => $status])->assertOk();
        }

        $body = $this->getJson('/api/admin/audit-logs?per_page=2')->assertOk()->json();

        $this->assertCount(2, $body['data']);
        $this->assertSame(2, $body['meta']['per_page']);
        $this->assertGreaterThanOrEqual(3, $body['meta']['total']);
        $this->assertGreaterThanOrEqual(2, $body['meta']['last_page']);

        // Newest first, and page 2 continues rather than repeating.
        $firstIds = array_column($body['data'], 'id');
        $secondIds = array_column($this->getJson('/api/admin/audit-logs?per_page=2&page=2')->json('data'), 'id');
        $this->assertEmpty(array_intersect($firstIds, $secondIds));

        $timestamps = array_column($body['data'], 'created_at');
        $sorted = $timestamps;
        rsort($sorted);
        $this->assertSame($sorted, $timestamps);
    }

    public function test_filters_endpoint_lists_actors_and_categories_from_the_files(): void
    {
        $admin = User::factory()->superAdmin()->create(['name' => 'Platform Boss']);
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin)
            ->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();

        $data = $this->getJson('/api/admin/audit-logs/filters')->assertOk()->json('data');

        $this->assertContains('restaurant', $data['categories']);
        $this->assertContains('restaurant.updated', $data['actions']);
        $this->assertContains($admin->id, array_column($data['actors'], 'id'));
    }

    // ---------------------------------------------------------- file listing

    public function test_files_endpoint_lists_each_day_with_its_event_count(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin)
            ->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();

        // A day that is not today, so the list has to show more than one file.
        File::put($this->dir.'/activity-2026-01-05.log', json_encode(['ts' => '2026-01-05T09:00:00+00:00', 'action' => 'auth.login'])."\n");

        $files = $this->getJson('/api/admin/audit-logs/files')->assertOk()->json('data');
        $byDate = collect($files)->keyBy('date');

        $this->assertTrue($byDate->has(now()->format('Y-m-d')));
        $this->assertSame(1, $byDate['2026-01-05']['events']);
        $this->assertSame('activity-2026-01-05.log', $byDate['2026-01-05']['filename']);
        $this->assertGreaterThan(0, $byDate['2026-01-05']['bytes']);

        // Newest first.
        $this->assertSame($files[0]['date'], collect($files)->max('date'));
    }

    public function test_a_day_file_can_be_downloaded_raw(): void
    {
        $admin = User::factory()->superAdmin()->create();
        File::put($this->dir.'/activity-2026-01-05.log', "{\"action\":\"auth.login\"}\n");

        $response = $this->actingAs($admin)->get('/api/admin/audit-logs/files/2026-01-05')->assertOk();

        $this->assertStringContainsString('activity-2026-01-05.log', $response->headers->get('content-disposition'));
        $this->assertSame("{\"action\":\"auth.login\"}\n", $response->getContent());
    }

    /**
     * A tenant's page must report that tenant's numbers: the same day file
     * counts differently depending on who is looking at it.
     */
    public function test_file_event_counts_are_scoped_to_the_requested_tenant(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $a = Restaurant::factory()->create(['status' => 'ACTIVE']);
        $b = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin);
        $this->patchJson("/api/admin/restaurants/{$a->id}/status", ['status' => 'SUSPENDED'])->assertOk();
        $this->patchJson("/api/admin/restaurants/{$b->id}/status", ['status' => 'SUSPENDED'])->assertOk();
        $this->patchJson("/api/admin/restaurants/{$b->id}/status", ['status' => 'ACTIVE'])->assertOk();

        $today = now()->format('Y-m-d');
        $countFor = function (?int $id) use ($today) {
            $query = $id ? "?restaurant_id={$id}" : '';
            $files = $this->getJson("/api/admin/audit-logs/files{$query}")->assertOk()->json('data');

            return collect($files)->firstWhere('date', $today)['events'];
        };

        // Truth comes from the file, not a guessed constant: how many events a
        // status change emits is an implementation detail, but the endpoint
        // must agree with what is actually on disk.
        $onDisk = fn (?int $id) => count(array_filter(
            $this->events(),
            fn ($e) => $id === null ? true : ($e['tenant_id'] ?? null) === $id
        ));

        $this->assertSame($onDisk($a->id), $countFor($a->id));
        $this->assertSame($onDisk($b->id), $countFor($b->id));
        $this->assertSame($onDisk(null), $countFor(null));

        // B was changed twice and A once, so B must genuinely out-count A —
        // otherwise the filter is not filtering at all.
        $this->assertGreaterThan($countFor($a->id), $countFor($b->id));
    }

    /** A download taken from a tenant's page carries only that tenant's lines. */
    public function test_a_tenant_scoped_download_excludes_other_tenants(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $a = Restaurant::factory()->create(['status' => 'ACTIVE']);
        $b = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin);
        $this->patchJson("/api/admin/restaurants/{$a->id}/status", ['status' => 'SUSPENDED'])->assertOk();
        $this->patchJson("/api/admin/restaurants/{$b->id}/status", ['status' => 'SUSPENDED'])->assertOk();

        $today = now()->format('Y-m-d');
        $body = $this->get("/api/admin/audit-logs/files/{$today}?restaurant_id={$a->id}")
            ->assertOk()->getContent();

        $lines = array_values(array_filter(explode("\n", $body)));
        $this->assertNotEmpty($lines);

        foreach ($lines as $line) {
            $this->assertSame($a->id, json_decode($line, true)['tenant_id']);
        }
    }

    /** The date comes from the URL, so it must resolve against known files, never a built path. */
    public function test_downloading_an_unknown_day_is_a_404(): void
    {
        $admin = User::factory()->superAdmin()->create();

        $this->actingAs($admin)->get('/api/admin/audit-logs/files/2019-01-01')->assertNotFound();
    }

    public function test_restaurant_admin_cannot_read_audit_logs(): void
    {
        $r = Restaurant::factory()->create();
        $staff = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($staff)->getJson('/api/admin/audit-logs')->assertForbidden();
        $this->actingAs($staff)->getJson('/api/admin/audit-logs/files')->assertForbidden();
    }
}
