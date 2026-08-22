<?php

namespace Tests\Feature\Admin;

use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Super Admin's per-restaurant table export. RestaurantScope is a no-op for
 * Super Admins, so the endpoint's own restaurant_id filter is the only thing
 * keeping one restaurant's floor out of another's export — that is what these
 * tests are really guarding.
 */
class RestaurantTablesExportTest extends TestCase
{
    use RefreshDatabase;

    private function makeTable(Restaurant $restaurant, string $label): DiningTable
    {
        $branch = new Branch(['name_en' => 'Main']);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        $area = new DiningArea(['branch_id' => $branch->id, 'name_en' => 'Indoor', 'is_active' => true]);
        $area->restaurant_id = $restaurant->id;
        $area->save();

        $table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => $label, 'seats_count' => 4,
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $table->restaurant_id = $restaurant->id;
        $table->branch_id = $branch->id;
        $table->save();

        return $table;
    }

    public function test_super_admin_exports_a_restaurants_tables_as_json(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['slug' => 'bistro']);
        $table = $this->makeTable($restaurant, '7');

        $res = $this->actingAs($sa)
            ->getJson("/api/admin/restaurants/{$restaurant->id}/tables/export")
            ->assertOk();

        $res->assertJsonPath('restaurant.slug', 'bistro');
        $res->assertJsonPath('count', 1);
        $res->assertJsonPath('data.0.label', '7');
        $res->assertJsonPath('data.0.public_token', $table->public_token);
        $res->assertJsonPath('data.0.url', $table->publicUrl());
        $res->assertJsonPath('data.0.area_name_en', 'Indoor');
        $res->assertJsonPath('data.0.qr_filename', "qr-7-{$table->public_token}.png");

        // The PNG rides along inline so the file stands on its own at a print shop.
        $png = base64_decode($res->json('data.0.qr_png_base64'), true);
        $this->assertStringStartsWith("\x89PNG", $png);
    }

    public function test_the_export_only_contains_the_requested_restaurants_tables(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $mine = Restaurant::factory()->create();
        $other = Restaurant::factory()->create();
        $this->makeTable($mine, '1');
        $this->makeTable($other, '2');

        $this->actingAs($sa)
            ->getJson("/api/admin/restaurants/{$mine->id}/tables/export")
            ->assertOk()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('data.0.label', '1');
    }

    public function test_a_restaurant_with_no_tables_exports_an_empty_list(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create();

        $this->actingAs($sa)
            ->getJson("/api/admin/restaurants/{$restaurant->id}/tables/export")
            ->assertOk()
            ->assertJsonPath('count', 0)
            ->assertJsonPath('data', []);
    }

    public function test_a_restaurant_admin_cannot_reach_the_admin_export(): void
    {
        $restaurant = Restaurant::factory()->create();
        $this->makeTable($restaurant, '1');
        $tenantAdmin = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->actingAs($tenantAdmin)
            ->getJson("/api/admin/restaurants/{$restaurant->id}/tables/export")
            ->assertForbidden();
    }

    public function test_the_export_requires_authentication(): void
    {
        $restaurant = Restaurant::factory()->create();

        $this->getJson("/api/admin/restaurants/{$restaurant->id}/tables/export")
            ->assertUnauthorized();
    }
}
