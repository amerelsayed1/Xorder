<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CombosTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $r = Restaurant::factory()->create();

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    private function itemFor(User $admin): MenuItem
    {
        $cat = Category::factory()->for($admin->restaurant)->create();

        return MenuItem::factory()->for($admin->restaurant)->for($cat)->create();
    }

    public function test_variant_combo_group_is_forced_single_select(): void
    {
        $admin = $this->admin();
        $item = $this->itemFor($admin);

        // Client marks the size group multi-select — the server must clamp it.
        $this->actingAs($admin)->postJson('/api/dashboard/combos', [
            'name_en' => 'Meal', 'base_price' => 0,
            'groups' => [[
                'name_en' => 'Size', 'is_variant' => true, 'max_select' => 4,
                'items' => [
                    ['menu_item_id' => $item->id, 'extra_price' => 120],
                    ['menu_item_id' => $item->id, 'extra_price' => 160],
                ],
            ]],
        ])->assertCreated();

        $this->assertDatabaseHas('combo_groups', [
            'name_en' => 'Size', 'is_variant' => true, 'max_select' => 1,
        ]);
    }

    public function test_public_menu_exposes_combo_is_variant_flag(): void
    {
        $admin = $this->admin();
        $item = $this->itemFor($admin);

        $this->actingAs($admin)->postJson('/api/dashboard/combos', [
            'name_en' => 'Meal', 'base_price' => 0, 'is_active' => true,
            'groups' => [[
                'name_en' => 'Size', 'is_variant' => true,
                'items' => [['menu_item_id' => $item->id, 'extra_price' => 120]],
            ]],
        ])->assertCreated();

        $slug = $admin->restaurant->slug;
        $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.combos.0.groups.0.is_variant', true);
    }
}
