<?php

namespace Tests\Feature;

use App\Enums\TenantCapability;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Plans cap how many staff accounts a restaurant may create. */
class PlanStaffLimitTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Role $role;

    private function onPlan(?int $maxStaff): User
    {
        Plan::create([
            'name' => 'Capped', 'price' => 10, 'currency' => 'EGP',
            'feature_keys' => [], 'max_staff' => $maxStaff, 'is_active' => true,
        ]);

        $this->restaurant = Restaurant::factory()->create(['subscription_plan' => 'Capped']);
        $this->role = new Role(['name' => 'Waiter']);
        $this->role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => TenantCapability::expand(['orders.view']),
        ])->save();

        return User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    private function addStaff(User $owner, string $username)
    {
        return $this->actingAs($owner)->postJson('/api/dashboard/staff', [
            'name' => $username, 'username' => $username, 'role_id' => $this->role->id,
        ]);
    }

    public function test_staff_can_be_added_up_to_the_plan_limit(): void
    {
        $owner = $this->onPlan(2);

        $this->addStaff($owner, 'one')->assertCreated();
        $this->addStaff($owner, 'two')->assertCreated();
    }

    public function test_the_next_account_past_the_limit_is_refused_with_the_number(): void
    {
        $owner = $this->onPlan(2);
        $this->addStaff($owner, 'one')->assertCreated();
        $this->addStaff($owner, 'two')->assertCreated();

        $this->addStaff($owner, 'three')
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.plan_limit_staff', ['limit' => 2]));

        $this->assertDatabaseMissing('users', ['username' => 'three']);
    }

    /**
     * The owner bought the plan; they do not occupy a seat sold under it. A
     * "1 user" plan must still allow one employee.
     */
    public function test_the_owner_does_not_consume_a_seat(): void
    {
        $owner = $this->onPlan(1);

        $this->addStaff($owner, 'only')->assertCreated();
        $this->addStaff($owner, 'second')->assertStatus(422);
    }

    /** A null limit means unlimited, so existing tenants are never capped by a deploy. */
    public function test_a_plan_without_a_limit_is_unlimited(): void
    {
        $owner = $this->onPlan(null);

        // Usernames must be at least 3 characters.
        foreach (['aaa', 'bbb', 'ccc', 'ddd', 'eee'] as $u) {
            $this->addStaff($owner, $u)->assertCreated();
        }
    }

    /** Deleting a staff account frees the seat. */
    public function test_removing_staff_frees_a_seat(): void
    {
        $owner = $this->onPlan(1);
        $this->addStaff($owner, 'first')->assertCreated();
        $this->addStaff($owner, 'second')->assertStatus(422);

        $first = User::where('username', 'first')->firstOrFail();
        $this->actingAs($owner)->deleteJson("/api/dashboard/staff/{$first->id}")->assertOk();

        $this->addStaff($owner, 'second')->assertCreated();
    }

    /** A tenant on no plan at all is not blocked. */
    public function test_a_restaurant_without_a_plan_is_unlimited(): void
    {
        $restaurant = Restaurant::factory()->create(['subscription_plan' => null]);
        $role = new Role(['name' => 'Waiter']);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand(['orders.view']),
        ])->save();
        $this->restaurant = $restaurant;
        $this->role = $role;

        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->addStaff($owner, 'anyone')->assertCreated();
    }
}
