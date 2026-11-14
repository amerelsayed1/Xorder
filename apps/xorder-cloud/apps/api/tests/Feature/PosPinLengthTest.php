<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * S2-2 (16 Oct 2026): the till's keypad submits on the fourth digit, so the
 * dashboard must not accept a PIN the till can never take. Exactly four, both
 * sides — a 5- or 6-digit PIN used to pass here and lock the cashier out.
 */
class PosPinLengthTest extends TestCase
{
    use RefreshDatabase;

    private function owner(): User
    {
        $restaurant = Restaurant::factory()->create();
        $restaurant->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    public function test_a_four_digit_pin_is_accepted(): void
    {
        $owner = $this->owner();

        $this->actingAs($owner)
            ->putJson("/api/dashboard/staff/{$owner->id}/pin", ['pin' => '4829'])
            ->assertOk()
            ->assertJsonPath('pin_set', true);
    }

    public function test_pins_the_till_keypad_cannot_take_are_refused(): void
    {
        $owner = $this->owner();

        foreach (['482', '48291', '482913', '48a9', '٤٨٢٩'] as $pin) {
            $this->actingAs($owner)
                ->putJson("/api/dashboard/staff/{$owner->id}/pin", ['pin' => $pin])
                ->assertStatus(422)
                ->assertJsonValidationErrors('pin');
        }

        $this->assertNull($owner->fresh()->pos_pin_hash);
    }
}
