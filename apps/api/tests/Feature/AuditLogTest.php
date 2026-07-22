<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuditLogTest extends TestCase
{
    use RefreshDatabase;

    public function test_successful_login_is_audited(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk();

        $this->assertDatabaseHas('audit_logs', ['action' => 'auth.login']);
    }

    public function test_failed_login_is_audited(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'nope'])
            ->assertStatus(401);

        $log = AuditLog::where('action', 'auth.login_failed')->first();
        $this->assertNotNull($log);
        $this->assertNull($log->actor_id);
    }

    public function test_status_change_is_audited_with_actor_and_tenant(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['status' => 'ACTIVE']);

        $this->actingAs($admin)
            ->patchJson("/api/admin/restaurants/{$restaurant->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();

        $log = AuditLog::where('action', 'restaurant.updated')
            ->where('restaurant_id', $restaurant->id)
            ->latest('id')
            ->first();

        $this->assertNotNull($log);
        $this->assertSame($admin->id, $log->actor_id);
        $this->assertSame('SUSPENDED', $log->properties['changes']['status']['new']);
    }

    public function test_index_filters_by_tenant_and_actor(): void
    {
        $admin = User::factory()->superAdmin()->create();
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();

        AuditLog::create(['restaurant_id' => $a->id, 'actor_id' => $admin->id, 'action' => 'restaurant.updated']);
        AuditLog::create(['restaurant_id' => $b->id, 'actor_id' => $admin->id, 'action' => 'restaurant.updated']);
        AuditLog::create(['restaurant_id' => $a->id, 'actor_id' => null, 'action' => 'auth.login_failed']);

        // Filter by tenant a → excludes tenant b's row.
        $byTenant = $this->actingAs($admin)->getJson("/api/admin/audit-logs?restaurant_id={$a->id}")->assertOk()->json('data');
        $this->assertGreaterThanOrEqual(2, count($byTenant));
        foreach ($byTenant as $row) {
            $this->assertSame($a->id, $row['tenant']['id']);
        }

        // Filter by actor + category.
        $byActor = $this->actingAs($admin)->getJson("/api/admin/audit-logs?actor_id={$admin->id}&category=restaurant")->assertOk()->json('data');
        foreach ($byActor as $row) {
            $this->assertSame($admin->id, $row['actor']['id']);
            $this->assertSame('restaurant', $row['category']);
        }
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

        // The deletion is audited, scoped to the platform (null tenant) so the
        // FK back to the removed restaurant doesn't dangle; the id survives in
        // auditable_id.
        $log = AuditLog::where('action', 'restaurant.deleted')->where('auditable_id', $rid)->first();
        $this->assertNotNull($log);
        $this->assertNull($log->restaurant_id);
    }

    public function test_restaurant_admin_cannot_read_audit_logs(): void
    {
        $r = Restaurant::factory()->create();
        $staff = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($staff)->getJson('/api/admin/audit-logs')->assertForbidden();
    }
}
