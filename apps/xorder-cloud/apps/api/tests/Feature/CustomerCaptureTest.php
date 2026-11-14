<?php

namespace Tests\Feature;

use App\Enums\OrderingMode;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * WhatsApp checkout records no order but still captures the diner, so a
 * restaurant keeps its customer directory across every ordering type.
 */
class CustomerCaptureTest extends TestCase
{
    use RefreshDatabase;

    public function test_whatsapp_checkout_saves_customer_without_an_order(): void
    {
        $r = Restaurant::factory()->withOrdering()->create([
            'slug' => 'wa-demo', 'ordering_mode' => OrderingMode::WHATSAPP,
        ]);

        $this->postJson('/api/public/restaurants/wa-demo/customers', [
            'customer_name' => 'Sara',
            'customer_phone' => '+201234567890',
            'customer_address' => '5 Nile St',
        ])->assertCreated();

        $this->assertDatabaseHas('customers', ['restaurant_id' => $r->id, 'name' => 'Sara']);
        $this->assertDatabaseHas('customer_addresses', ['address' => '5 Nile St']);
        // The whole point: no order is created for a WhatsApp checkout.
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_capture_requires_a_phone(): void
    {
        Restaurant::factory()->withOrdering()->create(['slug' => 'wa-demo']);

        $this->postJson('/api/public/restaurants/wa-demo/customers', ['customer_name' => 'NoPhone'])
            ->assertStatus(422)->assertJsonValidationErrors('customer_phone');
    }

    public function test_capture_404s_for_unknown_restaurant(): void
    {
        $this->postJson('/api/public/restaurants/ghost/customers', ['customer_phone' => '+201234567890'])
            ->assertStatus(404);
    }

    public function test_captured_customer_is_visible_in_directory_on_a_whatsapp_only_plan(): void
    {
        // WhatsApp-only plan: no system_ordering, no customer_tracking — the
        // restaurant must still see the customers it captured.
        $r = Restaurant::factory()->create(['slug' => 'wa-only', 'ordering_mode' => OrderingMode::WHATSAPP]);
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'whatsapp_ordering' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->postJson('/api/public/restaurants/wa-only/customers', [
            'customer_name' => 'Directory Guy', 'customer_phone' => '+201112223334',
        ])->assertCreated();

        $this->actingAs($admin)->getJson('/api/dashboard/customers')
            ->assertOk()->assertJsonFragment(['name' => 'Directory Guy']);
    }
}
