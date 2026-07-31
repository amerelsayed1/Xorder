<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CustomerTest extends TestCase
{
    use RefreshDatabase;

    /**
     * The customer directory holds PII (name/phone/addresses/order history) and
     * relies entirely on the global RestaurantScope for isolation — so pin it:
     * one restaurant's admin must never read another's customer.
     */
    public function test_cannot_view_another_restaurants_customer(): void
    {
        // Restaurant B takes a guest order, which upserts a directory customer.
        $rB = Restaurant::factory()->withOrdering()->create();
        $this->postJson("/api/public/restaurants/{$rB->slug}/orders", [
            'items' => [['name' => 'Burger', 'qty' => 1, 'line_total' => 100]],
            'total' => 100,
            'customer_name' => 'Bravo Guest',
            'customer_phone' => '+201112223334',
        ])->assertCreated();

        $customer = Customer::withoutGlobalScopes()->where('restaurant_id', $rB->id)->firstOrFail();

        // Restaurant A's admin tries to read B's customer → 404, not 403.
        $adminA = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();
        $this->actingAs($adminA)->getJson("/api/dashboard/customers/{$customer->id}")
            ->assertNotFound();
    }
}
