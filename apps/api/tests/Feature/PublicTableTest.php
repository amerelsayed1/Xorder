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
}
