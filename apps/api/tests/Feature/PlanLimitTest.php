<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PlanLimitTest extends TestCase
{
    use RefreshDatabase;

    private function itemPayload(int $categoryId): array
    {
        return [
            'category_id' => $categoryId,
            'name_en' => 'Burger',
            'name_ar' => 'برجر',
            'price' => 50,
        ];
    }

    public function test_item_create_blocked_at_plan_limit(): void
    {
        Plan::create(['name' => 'Starter', 'max_items' => 1]);
        $r = Restaurant::factory()->create(['subscription_plan' => 'Starter']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $cat = Category::factory()->for($r)->create();
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/items', $this->itemPayload($cat->id))
            ->assertStatus(422)
            ->assertJsonFragment(['message' => __('xorder.messages.plan_limit_items', ['limit' => 1])]);
    }

    public function test_item_create_allowed_below_limit_and_without_plan(): void
    {
        Plan::create(['name' => 'Pro', 'max_items' => 100]);
        $limited = Restaurant::factory()->create(['subscription_plan' => 'Pro']);
        $limitedAdmin = User::factory()->restaurantAdmin($limited->id)->create();
        $limitedCat = Category::factory()->for($limited)->create();

        $this->actingAs($limitedAdmin)
            ->postJson('/api/dashboard/items', $this->itemPayload($limitedCat->id))
            ->assertCreated();

        // No plan on file → unlimited (never block existing tenants).
        $free = Restaurant::factory()->create(['subscription_plan' => null]);
        $freeAdmin = User::factory()->restaurantAdmin($free->id)->create();
        $freeCat = Category::factory()->for($free)->create();

        $this->actingAs($freeAdmin)
            ->postJson('/api/dashboard/items', $this->itemPayload($freeCat->id))
            ->assertCreated();
    }

    public function test_branch_create_blocked_at_plan_limit(): void
    {
        Plan::create(['name' => 'Solo', 'max_branches' => 0]);
        $r = Restaurant::factory()->create(['subscription_plan' => 'Solo']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/branches', ['name_en' => 'Main'])
            ->assertStatus(422);
    }
}
