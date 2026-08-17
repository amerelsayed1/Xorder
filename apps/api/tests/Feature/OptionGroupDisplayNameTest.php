<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A shared Extras group carries two names: the one the owner files it under in
 * the library, and the heading a diner reads above the choices. The public menu
 * must show the second and never leak the first.
 */
class OptionGroupDisplayNameTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private MenuItem $item;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'bistro',
        ]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $category = Category::factory()->create([
            'restaurant_id' => $this->restaurant->id, 'is_active' => true,
        ]);
        $this->item = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => true,
        ]);
    }

    /** @return array<string,mixed> the first option group as the menu shows it */
    private function publicGroup(): array
    {
        $groups = $this->getJson('/api/public/restaurants/bistro/menu')
            ->assertOk()
            ->json('data.categories.0.items.0.option_groups');

        return $groups[0];
    }

    private function attachGroup(array $attributes): OptionGroup
    {
        $group = new OptionGroup($attributes + [
            'is_global' => true,
            'apply_scope' => OptionGroup::SCOPE_ALL,
            'max_select' => 1,
        ]);
        $group->restaurant_id = $this->restaurant->id;
        $group->save();

        return $group;
    }

    public function test_the_menu_shows_the_display_name_not_the_library_name(): void
    {
        $this->attachGroup([
            'name_en' => 'Sizes — pizza', 'name_ar' => 'أحجام — بيتزا',
            'display_name_en' => 'Choose your size', 'display_name_ar' => 'اختر الحجم',
        ]);

        $group = $this->publicGroup();

        $this->assertSame('Choose your size', $group['name_en']);
        $this->assertSame('اختر الحجم', $group['name_ar']);
        $this->assertStringNotContainsString('Sizes — pizza', json_encode($group, JSON_UNESCAPED_UNICODE));
    }

    public function test_the_library_name_is_used_when_no_display_name_is_set(): void
    {
        // Every group that existed before the split is in this state and must
        // keep rendering exactly as it did.
        $this->attachGroup(['name_en' => 'Extra toppings', 'name_ar' => 'إضافات']);

        $group = $this->publicGroup();

        $this->assertSame('Extra toppings', $group['name_en']);
        $this->assertSame('إضافات', $group['name_ar']);
    }

    public function test_each_language_falls_back_on_its_own(): void
    {
        // An owner who only rewrote the Arabic heading keeps the library name
        // in English rather than losing the English heading entirely.
        $this->attachGroup([
            'name_en' => 'Sizes', 'name_ar' => 'أحجام',
            'display_name_ar' => 'اختر الحجم',
        ]);

        $group = $this->publicGroup();

        $this->assertSame('Sizes', $group['name_en']);
        $this->assertSame('اختر الحجم', $group['name_ar']);
    }

    public function test_the_dashboard_saves_and_returns_both_names(): void
    {
        $res = $this->actingAs($this->admin)
            ->postJson('/api/dashboard/option-groups', [
                'name_en' => 'Sizes — pizza',
                'display_name_en' => 'Choose your size',
                'apply_scope' => 'items',
                'options' => [['name_en' => 'Large', 'price' => 10]],
            ])
            ->assertCreated();

        $res->assertJsonPath('data.name_en', 'Sizes — pizza')
            ->assertJsonPath('data.display_name_en', 'Choose your size');
    }

    public function test_clearing_the_display_name_falls_back_to_the_library_name(): void
    {
        $group = $this->attachGroup([
            'name_en' => 'Sizes', 'display_name_en' => 'Choose your size',
        ]);

        $this->actingAs($this->admin)
            ->putJson("/api/dashboard/option-groups/{$group->id}", ['display_name_en' => ''])
            ->assertOk();

        $this->assertSame('Sizes', $this->publicGroup()['name_en']);
    }
}
