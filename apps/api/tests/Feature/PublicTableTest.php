<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PublicTableTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Branch $branch;

    private DiningArea $area;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'bistro']);
        $this->branch = new Branch(['name_en' => 'Downtown']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();
        $this->area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Outdoor']);
        $this->area->restaurant_id = $this->restaurant->id;
        $this->area->save();
    }

    private function makeTable(string $label = '12', bool $active = true): DiningTable
    {
        $t = new DiningTable([
            'dining_area_id' => $this->area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'is_active' => $active,
            'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $this->restaurant->id;
        $t->branch_id = $this->branch->id;
        $t->save();

        return $t;
    }

    public function test_valid_token_returns_table_context(): void
    {
        $table = $this->makeTable('12');

        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertOk()
            ->assertJsonPath('data.restaurant.slug', 'bistro')
            ->assertJsonPath('data.table.label', '12')
            ->assertJsonPath('data.area.name_en', 'Outdoor')
            ->assertJsonPath('data.order_type', 'dine_in');
    }

    public function test_invalid_token_is_rejected(): void
    {
        $this->getJson('/api/public/tables/NOPE123456')->assertNotFound();
    }

    public function test_disabled_table_is_unavailable(): void
    {
        $table = $this->makeTable('9', active: false);

        $this->getJson("/api/public/tables/{$table->public_token}")->assertStatus(403);
    }

    public function test_disabled_branch_is_unavailable(): void
    {
        $table = $this->makeTable('4');
        $this->branch->update(['is_active' => false]);

        $this->getJson("/api/public/tables/{$table->public_token}")->assertStatus(403);
    }

    public function test_creating_a_session_persists_and_returns_a_token(): void
    {
        $table = $this->makeTable('7');

        $res = $this->postJson("/api/public/tables/{$table->public_token}/sessions", ['language' => 'en'])
            ->assertCreated()
            ->assertJsonPath('data.table.label', '7')
            ->assertJsonStructure(['data' => ['session_token', 'expires_at']]);

        $this->assertDatabaseHas('menu_sessions', [
            'session_token' => $res->json('data.session_token'),
            'table_id' => $table->id,
            'restaurant_id' => $this->restaurant->id,
            'language' => 'en',
        ]);
    }

    // ── Presence geofence ──────────────────────────────────────────────────

    /** A small square polygon fence around (30.00, 31.00). */
    private function enableFence(): void
    {
        $this->branch->update([
            'geofence_enabled' => true,
            'geofence' => ['type' => 'polygon', 'points' => [
                ['lat' => 29.99, 'lng' => 30.99],
                ['lat' => 29.99, 'lng' => 31.01],
                ['lat' => 30.01, 'lng' => 31.01],
                ['lat' => 30.01, 'lng' => 30.99],
            ]],
        ]);
    }

    /** A radius fence: 200 m around (30.00, 31.00). */
    private function enableRadiusFence(): void
    {
        $this->branch->update([
            'geofence_enabled' => true,
            'geofence' => ['type' => 'radius', 'center' => ['lat' => 30.0, 'lng' => 31.0], 'radius' => 200],
        ]);
    }

    public function test_context_advertises_when_a_fence_is_required(): void
    {
        $table = $this->makeTable('3');
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertOk()->assertJsonPath('data.geofence_required', false);

        $this->enableFence();
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertOk()->assertJsonPath('data.geofence_required', true);
    }

    public function test_context_advertises_a_fence_sized_accuracy_target(): void
    {
        $table = $this->makeTable('20');

        // No fence → no target for the client to aim at.
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertOk()->assertJsonPath('data.location_target_accuracy_m', null);

        // A 50 m radius fence → target ≈ half the radius (25 m), rounded to 5.
        $this->branch->update([
            'geofence_enabled' => true,
            'geofence' => ['type' => 'radius', 'center' => ['lat' => 30.0, 'lng' => 31.0], 'radius' => 50],
        ]);
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertOk()->assertJsonPath('data.location_target_accuracy_m', 25);
    }

    public function test_accuracy_target_is_clamped_for_large_and_tiny_fences(): void
    {
        $table = $this->makeTable('21');

        // Huge fence → capped at 60 m (don't wait forever for a big premises).
        $this->branch->update(['geofence_enabled' => true,
            'geofence' => ['type' => 'radius', 'center' => ['lat' => 30.0, 'lng' => 31.0], 'radius' => 500]]);
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertJsonPath('data.location_target_accuracy_m', 60);

        // Tiny fence → floored at 15 m (a precision phones can actually reach).
        $this->branch->update(['geofence_enabled' => true,
            'geofence' => ['type' => 'radius', 'center' => ['lat' => 30.0, 'lng' => 31.0], 'radius' => 10]]);
        $this->getJson("/api/public/tables/{$table->public_token}")
            ->assertJsonPath('data.location_target_accuracy_m', 15);
    }

    public function test_session_allowed_when_gps_is_inside_the_fence(): void
    {
        $this->enableFence();
        $table = $this->makeTable('5');

        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'language' => 'en', 'latitude' => 30.0, 'longitude' => 31.0,
        ])->assertCreated()->assertJsonStructure(['data' => ['session_token']]);
    }

    public function test_session_blocked_when_gps_is_outside_the_fence(): void
    {
        $this->enableFence();
        $table = $this->makeTable('6');

        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 40.0, 'longitude' => 41.0,
        ])->assertStatus(422);

        $this->assertDatabaseCount('menu_sessions', 0);
    }

    public function test_session_blocked_when_gps_missing_and_fence_required(): void
    {
        $this->enableFence();
        $table = $this->makeTable('8');

        // Fails closed: no coordinates → refused, no spoofable fallback.
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", ['language' => 'en'])
            ->assertStatus(422);

        $this->assertDatabaseCount('menu_sessions', 0);
    }

    public function test_radius_fence_allows_inside_and_blocks_outside(): void
    {
        $this->enableRadiusFence();
        $table = $this->makeTable('11');

        // ~30 m from centre → inside the 200 m radius.
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 30.0002, 'longitude' => 31.0002,
        ])->assertCreated();

        // Several km away → outside.
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 30.1, 'longitude' => 31.1,
        ])->assertStatus(422);
    }

    public function test_accuracy_tolerance_admits_a_fuzzy_fix_just_outside_the_fence(): void
    {
        $this->enableRadiusFence();
        $table = $this->makeTable('13');

        // ~222 m from centre → outside the 200 m radius on its own...
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 30.002, 'longitude' => 31.0,
        ])->assertStatus(422);

        // ...but a 60 m GPS accuracy widens the fence enough to admit it.
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 30.002, 'longitude' => 31.0, 'accuracy' => 60,
        ])->assertCreated();
    }

    public function test_accuracy_tolerance_is_capped_and_cannot_defeat_the_fence(): void
    {
        $this->enableRadiusFence();
        $table = $this->makeTable('14');

        // A wildly uncertain fix (e.g. IP-only) several km away stays blocked
        // even with an enormous reported accuracy — the tolerance is capped.
        $this->postJson("/api/public/tables/{$table->public_token}/sessions", [
            'latitude' => 30.1, 'longitude' => 31.1, 'accuracy' => 100000,
        ])->assertStatus(422);

        $this->assertDatabaseCount('menu_sessions', 0);
    }

    public function test_gps_ignored_when_fence_disabled(): void
    {
        // Polygon drawn but the toggle is off → ordinary behaviour, no check.
        $this->branch->update(['geofence_enabled' => false, 'geofence' => [
            ['lat' => 29.99, 'lng' => 30.99], ['lat' => 29.99, 'lng' => 31.01], ['lat' => 30.01, 'lng' => 31.0],
        ]]);
        $table = $this->makeTable('10');

        $this->postJson("/api/public/tables/{$table->public_token}/sessions", ['language' => 'en'])
            ->assertCreated();
    }
}
