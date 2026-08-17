<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Dashboard-home counters.
 *
 * The counters answer "what can a diner order right now?", so they have to
 * agree with what the public menu actually loads — which skips switched-off
 * categories entirely.
 */
class DashboardStatsTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    private function category(bool $active): Category
    {
        return Category::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'is_active' => $active,
        ]);
    }

    private function item(Category $category, bool $available = true): MenuItem
    {
        return MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => $available,
        ]);
    }

    private function stats(): array
    {
        return $this->actingAs($this->admin)
            ->getJson('/api/dashboard/stats')
            ->assertOk()
            ->json('data');
    }

    public function test_items_in_an_inactive_category_do_not_count_as_available(): void
    {
        $live = $this->category(true);
        $hidden = $this->category(false);

        $this->item($live);
        $this->item($live);
        $this->item($hidden);   // available flag on, but its category is off

        $stats = $this->stats();

        $this->assertSame(3, $stats['total_items'], 'the owner still has three items');
        $this->assertSame(2, $stats['available_items'], 'only the two a diner can reach');
        $this->assertSame(1, $stats['unavailable_items']);
    }

    public function test_an_unavailable_item_in_an_active_category_still_counts_as_unavailable(): void
    {
        $live = $this->category(true);
        $this->item($live);
        $this->item($live, available: false);

        $stats = $this->stats();

        $this->assertSame(2, $stats['total_items']);
        $this->assertSame(1, $stats['available_items']);
        $this->assertSame(1, $stats['unavailable_items']);
    }

    public function test_switching_a_category_off_moves_its_items_to_unavailable(): void
    {
        $category = $this->category(true);
        $this->item($category);
        $this->item($category);

        $this->assertSame(2, $this->stats()['available_items']);

        $category->update(['is_active' => false]);

        $after = $this->stats();
        $this->assertSame(0, $after['available_items']);
        $this->assertSame(2, $after['unavailable_items']);
        $this->assertSame(2, $after['total_items'], 'nothing was deleted, only hidden');
    }

    public function test_counters_never_reach_across_tenants(): void
    {
        $mine = $this->category(true);
        $this->item($mine);

        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $theirCategory = Category::factory()->create(['restaurant_id' => $other->id, 'is_active' => true]);
        MenuItem::factory()->count(4)->create([
            'restaurant_id' => $other->id,
            'category_id' => $theirCategory->id,
            'is_available' => true,
        ]);

        $stats = $this->stats();

        $this->assertSame(1, $stats['total_items']);
        $this->assertSame(1, $stats['available_items']);
    }
}
