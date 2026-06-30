<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PlanTest extends TestCase
{
    use RefreshDatabase;

    public function test_plans_require_super_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/admin/plans')->assertForbidden();
    }

    public function test_plans_are_unreachable_when_unauthenticated(): void
    {
        $this->getJson('/api/admin/plans')->assertUnauthorized();
    }

    public function test_super_admin_can_create_plan_with_features(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/plans', [
            'name' => 'Pro',
            'price' => 500,
            'currency' => 'EGP',
            'features' => ['Unlimited items', 'QR code'],
            'is_active' => true,
            'sort_order' => 2,
        ])->assertCreated()
            ->assertJsonPath('data.name', 'Pro')
            ->assertJsonPath('data.features.0', 'Unlimited items')
            ->assertJsonPath('data.is_active', true);

        $this->assertDatabaseHas('plans', ['name' => 'Pro', 'price' => 500]);
    }

    public function test_plan_name_is_required_and_unique(): void
    {
        $sa = User::factory()->superAdmin()->create();
        Plan::create(['name' => 'Basic', 'currency' => 'EGP']);

        $this->actingAs($sa)->postJson('/api/admin/plans', ['currency' => 'EGP'])
            ->assertStatus(422)->assertJsonValidationErrors('name');

        $this->actingAs($sa)->postJson('/api/admin/plans', ['name' => 'Basic', 'currency' => 'EGP'])
            ->assertStatus(422)->assertJsonValidationErrors('name');
    }

    public function test_super_admin_can_update_and_delete_plan(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $plan = Plan::create(['name' => 'Basic', 'price' => 100, 'currency' => 'EGP', 'is_active' => true]);

        $this->actingAs($sa)->putJson("/api/admin/plans/{$plan->id}", ['price' => 150, 'is_active' => false])
            ->assertOk()
            ->assertJsonPath('data.is_active', false);
        $this->assertDatabaseHas('plans', ['id' => $plan->id, 'price' => 150, 'is_active' => false]);

        $this->actingAs($sa)->deleteJson("/api/admin/plans/{$plan->id}")->assertOk();
        $this->assertDatabaseMissing('plans', ['id' => $plan->id]);
    }

    public function test_active_only_filter_excludes_inactive_plans(): void
    {
        $sa = User::factory()->superAdmin()->create();
        Plan::create(['name' => 'Live', 'currency' => 'EGP', 'is_active' => true]);
        Plan::create(['name' => 'Hidden', 'currency' => 'EGP', 'is_active' => false]);

        $this->actingAs($sa)->getJson('/api/admin/plans?active_only=1')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Live');
    }
}
