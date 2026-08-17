<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Category serving times end to end: what the owner saves, and what the public
 * menu then says about it.
 *
 * The product rule here is deliberate — an out-of-hours category stays on the
 * menu rather than disappearing, so a diner can see that breakfast exists and
 * when it comes back. Only its availability flips.
 */
class CategoryAvailabilityTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'bistro', 'timezone' => 'Africa/Cairo',
        ]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    private function category(?array $hours, string $name = 'Breakfast'): Category
    {
        $category = Category::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'name_en' => $name,
            'is_active' => true,
            'availability_hours' => $hours,
        ]);
        MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => true,
        ]);

        return $category;
    }

    /** Freeze the clock at a wall time in the restaurant's own timezone. */
    private function atCairo(string $datetime): void
    {
        Carbon::setTestNow(Carbon::parse($datetime, 'Africa/Cairo'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function menuCategory(): array
    {
        return $this->getJson('/api/public/restaurants/bistro/menu')
            ->assertOk()
            ->json('data.categories.0');
    }

    // ── What the diner is told ─────────────────────────────────────────────

    public function test_a_category_in_hours_is_available(): void
    {
        $this->category(['sun' => ['open' => '07:00', 'close' => '11:00']]);
        $this->atCairo('2026-08-16 09:00');   // a Sunday

        $this->assertTrue($this->menuCategory()['available_now']);
    }

    public function test_a_category_out_of_hours_stays_on_the_menu_but_is_unavailable(): void
    {
        $this->category(['sun' => ['open' => '07:00', 'close' => '11:00']]);
        $this->atCairo('2026-08-16 15:00');

        $category = $this->menuCategory();

        $this->assertFalse($category['available_now']);
        $this->assertSame('Breakfast', $category['name_en'], 'it must not vanish from the menu');
        $this->assertCount(1, $category['items'], 'its items stay visible too');
    }

    public function test_the_window_is_published_so_the_menu_can_say_when_it_returns(): void
    {
        $this->category(['sun' => ['open' => '07:00', 'close' => '11:00']]);
        $this->atCairo('2026-08-16 15:00');

        $this->assertSame(['open' => '07:00', 'close' => '11:00'], $this->menuCategory()['available_window']);
    }

    public function test_a_category_with_no_hours_is_always_available(): void
    {
        $this->category(null);
        $this->atCairo('2026-08-16 04:00');

        $category = $this->menuCategory();

        $this->assertTrue($category['available_now']);
        $this->assertNull($category['availability_hours']);
    }

    public function test_hours_are_judged_in_the_restaurant_timezone_not_the_server_one(): void
    {
        // Cairo runs UTC+3 in August, so 07:00 UTC is 10:00 there. The window
        // brackets 10:00 Cairo and excludes 07:00, so this can only pass if the
        // restaurant's timezone is what was used.
        $this->category(['sun' => ['open' => '09:30', 'close' => '10:30']]);
        Carbon::setTestNow(Carbon::parse('2026-08-16 07:00', 'UTC'));

        $this->assertTrue($this->menuCategory()['available_now']);
    }

    public function test_the_restaurant_timezone_can_also_close_a_category_the_server_clock_would_leave_open(): void
    {
        // The same offset in the other direction: 21:00 UTC is 00:00 Monday in
        // Cairo, past the end of Sunday's window.
        $this->category(['sun' => ['open' => '09:00', 'close' => '22:00'], 'mon' => ['closed' => true]]);
        Carbon::setTestNow(Carbon::parse('2026-08-16 21:00', 'UTC'));

        $this->assertFalse($this->menuCategory()['available_now']);
    }

    // ── The featured rail must not offer what is out of hours ──────────────

    public function test_a_featured_item_from_an_out_of_hours_category_is_not_in_the_featured_rail(): void
    {
        $category = $this->category(['sun' => ['open' => '07:00', 'close' => '11:00']]);
        MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => true,
            'is_featured' => true,
        ]);
        $this->atCairo('2026-08-16 15:00');

        $payload = $this->getJson('/api/public/restaurants/bistro/menu')->assertOk();

        $this->assertCount(0, $payload->json('data.featured'));
        // …but it is still there inside its own section, which explains why.
        $this->assertCount(2, $payload->json('data.categories.0.items'));
    }

    public function test_a_featured_item_in_hours_is_still_promoted(): void
    {
        $category = $this->category(['sun' => ['open' => '07:00', 'close' => '11:00']]);
        MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => true,
            'is_featured' => true,
        ]);
        $this->atCairo('2026-08-16 09:00');

        $this->assertCount(1, $this->getJson('/api/public/restaurants/bistro/menu')->json('data.featured'));
    }

    // ── The dashboard side ─────────────────────────────────────────────────

    public function test_an_owner_can_save_and_clear_serving_times(): void
    {
        $category = $this->category(null);

        $this->actingAs($this->admin)
            ->putJson("/api/dashboard/categories/{$category->id}", [
                'name_en' => 'Breakfast',
                'availability_hours' => ['sun' => ['closed' => false, 'always' => false, 'open' => '07:00', 'close' => '11:00']],
            ])
            ->assertOk()
            ->assertJsonPath('data.availability_hours.sun.open', '07:00');

        $this->actingAs($this->admin)
            ->putJson("/api/dashboard/categories/{$category->id}", [
                'name_en' => 'Breakfast', 'availability_hours' => null,
            ])
            ->assertOk()
            ->assertJsonPath('data.availability_hours', null);
    }

    public function test_a_malformed_time_is_rejected(): void
    {
        $category = $this->category(null);

        $this->actingAs($this->admin)
            ->putJson("/api/dashboard/categories/{$category->id}", [
                'name_en' => 'Breakfast',
                'availability_hours' => ['sun' => ['open' => '25:99', 'close' => '11:00']],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('availability_hours.sun.open');
    }
}
