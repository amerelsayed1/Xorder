<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantStatsTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_gets_restaurant_counts_by_status(): void
    {
        $sa = User::factory()->superAdmin()->create();

        Restaurant::factory()->count(2)->create(['status' => RestaurantStatus::ACTIVE]);
        Restaurant::factory()->create(['status' => RestaurantStatus::SUSPENDED]);
        Restaurant::factory()->count(3)->create(['status' => RestaurantStatus::ARCHIVED]);

        $this->actingAs($sa)->getJson('/api/admin/restaurants/stats')
            ->assertOk()
            ->assertExactJson([
                'data' => [
                    'total' => 6,
                    'by_status' => [
                        'ACTIVE' => 2,
                        'SUSPENDED' => 1,
                        'ARCHIVED' => 3,
                    ],
                ],
            ]);
    }

    public function test_stats_returns_zeroed_statuses_when_empty(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->getJson('/api/admin/restaurants/stats')
            ->assertOk()
            ->assertExactJson([
                'data' => [
                    'total' => 0,
                    'by_status' => [
                        'ACTIVE' => 0,
                        'SUSPENDED' => 0,
                        'ARCHIVED' => 0,
                    ],
                ],
            ]);
    }

    public function test_stats_route_is_not_shadowed_by_show_and_requires_super_admin(): void
    {
        // A restaurant admin (non-super) must be forbidden — proves the route
        // resolves to stats() under the SUPER_ADMIN group, not the {restaurant}
        // wildcard treating "stats" as an id.
        $admin = User::factory()->create();

        $this->actingAs($admin)->getJson('/api/admin/restaurants/stats')
            ->assertForbidden();
    }
}
