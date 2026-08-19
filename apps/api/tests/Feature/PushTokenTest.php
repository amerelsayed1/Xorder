<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\DeviceToken;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * FCM device registration for admin push notifications.
 *
 * DeviceToken is one of the few tenant-owning models with no global scope, so
 * the isolation here is hand-written — which is exactly the kind of thing that
 * should be pinned by tests rather than left to a future refactor's good
 * intentions. New-order pushes carry customer names and table numbers, so a
 * mis-routed token leaks live operational data to another business.
 */
class PushTokenTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private const TOKEN = 'fcm-token-abc123';

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    public function test_an_admin_registers_their_device(): void
    {
        $this->actingAs($this->admin)
            ->postJson('/api/dashboard/push/token', ['token' => self::TOKEN, 'platform' => 'web'])
            ->assertOk();

        $this->assertDatabaseHas('device_tokens', [
            'token' => self::TOKEN,
            'user_id' => $this->admin->id,
            'restaurant_id' => $this->restaurant->id,
        ]);
    }

    public function test_re_registering_the_same_device_does_not_duplicate_it(): void
    {
        foreach ([1, 2] as $_) {
            $this->actingAs($this->admin)
                ->postJson('/api/dashboard/push/token', ['token' => self::TOKEN])
                ->assertOk();
        }

        $this->assertSame(1, DeviceToken::where('token', self::TOKEN)->count());
    }

    public function test_another_tenant_cannot_repoint_a_token_that_is_already_registered(): void
    {
        // The attack this guards: an admin who obtains another tenant's FCM
        // token POSTs it here to redirect that device's push routing — and
        // with it, the other restaurant's live order stream.
        $this->actingAs($this->admin)
            ->postJson('/api/dashboard/push/token', ['token' => self::TOKEN])
            ->assertOk();

        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $intruder = User::factory()->restaurantAdmin($other->id)->create();

        // Answers exactly as a success would — no oracle telling the caller
        // whether that token existed.
        $this->actingAs($intruder)
            ->postJson('/api/dashboard/push/token', ['token' => self::TOKEN])
            ->assertOk();

        $this->assertDatabaseHas('device_tokens', [
            'token' => self::TOKEN,
            'user_id' => $this->admin->id,
            'restaurant_id' => $this->restaurant->id,
        ]);
        $this->assertDatabaseMissing('device_tokens', [
            'token' => self::TOKEN, 'restaurant_id' => $other->id,
        ]);
    }

    public function test_an_admin_can_drop_their_own_token(): void
    {
        $this->actingAs($this->admin)->postJson('/api/dashboard/push/token', ['token' => self::TOKEN]);

        $this->actingAs($this->admin)
            ->deleteJson('/api/dashboard/push/token', ['token' => self::TOKEN])
            ->assertOk();

        $this->assertDatabaseMissing('device_tokens', ['token' => self::TOKEN]);
    }

    public function test_one_admin_cannot_delete_another_admins_token(): void
    {
        $this->actingAs($this->admin)->postJson('/api/dashboard/push/token', ['token' => self::TOKEN]);

        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $intruder = User::factory()->restaurantAdmin($other->id)->create();

        $this->actingAs($intruder)
            ->deleteJson('/api/dashboard/push/token', ['token' => self::TOKEN])
            ->assertOk();

        $this->assertDatabaseHas('device_tokens', ['token' => self::TOKEN, 'user_id' => $this->admin->id]);
    }

    public function test_registration_requires_authentication(): void
    {
        $this->postJson('/api/dashboard/push/token', ['token' => self::TOKEN])->assertUnauthorized();
    }
}
