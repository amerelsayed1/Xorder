<?php

namespace Tests\Feature;

use App\Enums\TenantCapability;
use App\Models\Category;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\TestCase;

/**
 * XORD-007 — several categories in one request, all-or-nothing.
 */
class BulkCategoriesTest extends TestCase
{
    use RefreshDatabase;

    private function admin(array $restaurant = []): User
    {
        return User::factory()->restaurantAdmin(Restaurant::factory()->create($restaurant)->id)->create();
    }

    private function bulk(User $user, array $rows)
    {
        return $this->actingAs($user)->postJson('/api/dashboard/categories/bulk', ['categories' => $rows]);
    }

    public function test_creates_every_row_in_order_after_the_existing_ones(): void
    {
        $admin = $this->admin();
        Category::factory()->for($admin->restaurant)->create(['display_order' => 4]);

        $this->bulk($admin, [
            ['name_en' => 'Starters', 'name_ar' => 'مقبلات'],
            ['name_en' => 'Mains'],
            ['name_ar' => 'حلويات'],
        ])->assertCreated()->assertJsonCount(3, 'data');

        $made = Category::query()->whereIn('name_en', ['Starters', 'Mains'])->orWhere('name_ar', 'حلويات')->orderBy('display_order')->get();
        $this->assertCount(3, $made);
        $this->assertSame([5, 6, 7], $made->pluck('display_order')->all());
        $this->assertSame(['Starters', 'Mains', null], $made->pluck('name_en')->all());
    }

    public function test_names_are_trimmed_and_a_blank_name_is_no_name(): void
    {
        $admin = $this->admin();

        $this->bulk($admin, [['name_en' => '  Drinks  ', 'name_ar' => '   ']])->assertCreated();

        $this->assertSame('Drinks', Category::query()->firstOrFail()->name_en);
        $this->assertNull(Category::query()->firstOrFail()->name_ar);
    }

    public function test_a_name_already_on_the_menu_refuses_the_whole_batch(): void
    {
        $admin = $this->admin();
        Category::factory()->for($admin->restaurant)->create(['name_en' => 'Drinks']);

        $this->bulk($admin, [['name_en' => 'Starters'], ['name_en' => 'Drinks']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('categories.1.name_en');

        $this->assertSame(1, Category::query()->count(), 'nothing from the batch was stored');
    }

    public function test_a_name_repeated_inside_the_batch_is_refused(): void
    {
        $admin = $this->admin();

        $this->bulk($admin, [['name_en' => 'Drinks'], ['name_en' => 'Mains'], ['name_en' => 'Drinks']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('categories.2.name_en');

        $this->assertSame(0, Category::query()->count());
    }

    public function test_a_row_with_no_name_is_refused_on_the_default_language_field(): void
    {
        $admin = $this->admin(['default_language' => 'ar', 'bilingual' => false]);

        $this->bulk($admin, [['name_ar' => 'مشروبات'], []])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('categories.1.name_ar');

        $this->assertSame(0, Category::query()->count());
    }

    public function test_the_same_name_in_another_restaurant_is_no_conflict(): void
    {
        $other = $this->admin();
        Category::factory()->for($other->restaurant)->create(['name_en' => 'Drinks']);

        $this->bulk($this->admin(), [['name_en' => 'Drinks']])->assertCreated();
    }

    public function test_the_plan_cap_counts_the_whole_batch_and_stores_none_of_it(): void
    {
        Plan::create(['name' => 'Starter', 'max_categories' => 3]);
        $admin = $this->admin(['subscription_plan' => 'Starter']);
        Category::factory()->for($admin->restaurant)->count(2)->create();

        $this->bulk($admin, [['name_en' => 'A'], ['name_en' => 'B']])
            ->assertUnprocessable()
            ->assertJsonFragment(['message' => __('xorder.messages.plan_limit_categories', ['limit' => 3])]);

        $this->assertSame(2, Category::query()->count());

        // One fits.
        $this->bulk($admin, [['name_en' => 'A']])->assertCreated();
    }

    public function test_a_failure_part_way_through_rolls_every_row_back(): void
    {
        $admin = $this->admin();
        Category::creating(function (Category $category) {
            if ($category->name_en === 'Third') {
                throw new RuntimeException('disk full');
            }
        });

        $this->withoutExceptionHandling();
        try {
            $this->bulk($admin, [['name_en' => 'First'], ['name_en' => 'Second'], ['name_en' => 'Third']]);
            $this->fail('the exception should have escaped the request');
        } catch (RuntimeException) {
            // expected
        }

        $this->assertSame(0, Category::query()->count(), 'all-or-nothing');
    }

    public function test_the_batch_has_a_ceiling(): void
    {
        $admin = $this->admin();
        $rows = array_map(fn ($i) => ['name_en' => "Cat {$i}"], range(1, 51));

        $this->bulk($admin, $rows)->assertUnprocessable()->assertJsonValidationErrors('categories');
        $this->assertSame(0, Category::query()->count());
    }

    public function test_staff_without_menu_create_is_refused(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = new Role(['name' => 'Viewer']);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand(['menu.view']),
            'is_system' => false,
        ])->save();
        $viewer = User::factory()->staff($restaurant->id, $role->id)->create();

        $this->bulk($viewer, [['name_en' => 'X']])->assertForbidden();
        $this->assertSame(0, Category::query()->count());
    }

    public function test_it_needs_a_login(): void
    {
        $this->postJson('/api/dashboard/categories/bulk', ['categories' => [['name_en' => 'X']]])
            ->assertUnauthorized();
    }
}
