<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Rules\MobileNumber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Validator;
use Tests\Concerns\BuildsDinerOrders;
use Tests\TestCase;

class PhoneValidationTest extends TestCase
{
    use BuildsDinerOrders;
    use RefreshDatabase;

    private function passes(mixed $value, ?MobileNumber $rule = null): bool
    {
        return Validator::make(
            ['phone' => $value],
            ['phone' => ['nullable', $rule ?? new MobileNumber]]
        )->passes();
    }

    public function test_accepts_valid_egyptian_mobile_in_local_and_international_form(): void
    {
        $this->assertTrue($this->passes('01012345678'));
        $this->assertTrue($this->passes('+201012345678'));
    }

    public function test_accepts_arabic_and_persian_digits(): void
    {
        $this->assertTrue($this->passes('٠١٠١٢٣٤٥٦٧٨')); // Arabic-Indic 01012345678
        $this->assertTrue($this->passes('۰۱۰۱۲۳۴۵۶۷۸')); // Persian 01012345678
    }

    public function test_respects_each_countrys_rules_for_international_numbers(): void
    {
        // Valid Saudi mobile, even though the default parsing country is EG.
        $this->assertTrue($this->passes('+966512345678'));
        // Too short for Saudi.
        $this->assertFalse($this->passes('+9665123'));
    }

    public function test_rejects_malformed_numbers(): void
    {
        $this->assertFalse($this->passes('0123'));             // too short
        $this->assertFalse($this->passes('010123456789999'));  // too long
        $this->assertFalse($this->passes('not-a-number'));     // letters
    }

    public function test_landline_rejected_by_default_but_allowed_when_opted_in(): void
    {
        $cairoLandline = '0225770000';
        $this->assertFalse($this->passes($cairoLandline));
        $this->assertTrue($this->passes($cairoLandline, (new MobileNumber)->allowLandline()));
    }

    public function test_nullable_and_empty_values_pass(): void
    {
        $this->assertTrue($this->passes(null));
        $this->assertTrue($this->passes(''));
        $this->assertTrue($this->passes('   '));
    }

    public function test_order_endpoint_rejects_an_invalid_customer_phone(): void
    {
        Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $this->postJson('/api/public/restaurants/demo/orders', [
            'items' => $this->dinerItems([['name' => 'Pizza', 'qty' => 1, 'options' => [], 'line_total' => 80]]),
            'total' => 80,
            'customer_name' => 'Amer',
            'customer_phone' => '123',
        ])->assertStatus(422)->assertJsonValidationErrors('customer_phone');
    }

    public function test_order_endpoint_normalizes_arabic_digits_before_storing(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $this->postJson('/api/public/restaurants/demo/orders', [
            'items' => $this->dinerItems([['name' => 'Pizza', 'qty' => 1, 'options' => [], 'line_total' => 80]]),
            'total' => 80,
            'customer_name' => 'Amer',
            'customer_phone' => '٠١٠١٢٣٤٥٦٧٨',
        ])->assertCreated();

        // Stored on both the order snapshot and the directory customer in Latin.
        $this->assertDatabaseHas('orders', [
            'restaurant_id' => $r->id,
            'customer_phone' => '01012345678',
        ]);
        $this->assertDatabaseHas('customers', [
            'restaurant_id' => $r->id,
            'phone' => '01012345678',
        ]);
    }
}
