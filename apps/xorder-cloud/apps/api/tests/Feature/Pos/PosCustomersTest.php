<?php

namespace Tests\Feature\Pos;

use App\Enums\TenantCapability;
use App\Models\Customer;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Support\Str;

/**
 * POS-BE-014 — a customer created at the counter.
 *
 * The contract was agreed 2026-09-02 and asked for one thing above all: reuse
 * `CustomerDirectory::upsert()` rather than writing a second creation path,
 * "so POS-created and diner-created customers deduplicate to one identity."
 * The tests that matter here are the ones that would catch a second path
 * appearing — one directory, one phone, one person.
 */
class PosCustomersTest extends PosTestCase
{
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->token = $this->claimTerminal()['token'];
    }

    /** @return array<string,mixed> */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'name' => 'Amer',
            'phone' => '01016943505',
            'address' => '12 Road 9, Maadi',
        ], $overrides);
    }

    public function test_a_cashier_can_add_a_customer_at_the_counter(): void
    {
        $body = $this->postJson('/api/pos/customers', $this->payload(), $this->deviceHeaders($this->token))
            ->assertCreated()
            ->json('data');

        $this->assertSame('Amer', $body['name']);
        $this->assertSame('12 Road 9, Maadi', $body['address']);

        TenantContext::overrideId($this->restaurant->id);
        try {
            $this->assertSame(1, Customer::count());
            $this->assertSame($this->restaurant->id, Customer::first()->restaurant_id);
        } finally {
            TenantContext::clearOverride();
        }
    }

    public function test_the_same_number_is_the_same_person_however_it_arrived(): void
    {
        // The whole point of the contract. A regular who has ordered from
        // their phone and then gives the same number at the counter must not
        // become a second row — a split directory is invisible until somebody
        // asks "how often does this customer order", and by then it is months
        // of data.
        $this->postJson('/api/pos/customers', $this->payload(), $this->deviceHeaders($this->token))
            ->assertCreated();

        $again = $this->postJson('/api/pos/customers', $this->payload([
            'name' => 'Amer El Sayed',
        ]), $this->deviceHeaders($this->token));

        // 200, not 201: nobody new was created.
        $again->assertOk();

        TenantContext::overrideId($this->restaurant->id);
        try {
            $this->assertSame(1, Customer::count());
            $this->assertSame('Amer El Sayed', Customer::first()->name);
        } finally {
            TenantContext::clearOverride();
        }
    }

    public function test_arabic_indic_digits_reach_the_same_customer(): void
    {
        // `CustomerDirectory` normalises before it keys. If the till ever grew
        // its own normalisation the directory would split on exactly this.
        $this->postJson('/api/pos/customers', $this->payload(), $this->deviceHeaders($this->token))
            ->assertCreated();

        $this->postJson('/api/pos/customers', $this->payload([
            'phone' => '٠١٠١٦٩٤٣٥٠٥',
        ]), $this->deviceHeaders($this->token))->assertOk();

        TenantContext::overrideId($this->restaurant->id);
        try {
            $this->assertSame(1, Customer::count());
        } finally {
            TenantContext::clearOverride();
        }
    }

    public function test_a_named_cashier_needs_the_verb(): void
    {
        $role = new Role(['name' => 'Cashier']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => [TenantCapability::POS_OPERATE->value]])->save();
        $cashier = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->postJson('/api/pos/customers', $this->payload([
            'acting_user_id' => $cashier->id,
        ]), $this->deviceHeaders($this->token))
            ->assertStatus(403)
            ->assertJsonPath('code', 'POS_CAPABILITY_MISSING');

        $role->forceFill(['capabilities' => [
            TenantCapability::POS_OPERATE->value,
            TenantCapability::CUSTOMERS_CREATE->value,
        ]])->save();

        $this->postJson('/api/pos/customers', $this->payload([
            'acting_user_id' => $cashier->id,
        ]), $this->deviceHeaders($this->token))->assertCreated();
    }

    public function test_a_customer_with_no_phone_cannot_be_found_again_so_is_refused(): void
    {
        $this->postJson('/api/pos/customers', $this->payload(['phone' => '']), $this->deviceHeaders($this->token))
            ->assertStatus(422);
    }

    public function test_the_bundle_carries_the_directory_so_the_till_can_search_offline(): void
    {
        $this->postJson('/api/pos/customers', $this->payload(), $this->deviceHeaders($this->token))
            ->assertCreated();

        $bundle = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($this->token))
            ->assertOk()
            ->json('customers');

        $this->assertCount(1, $bundle);
        $this->assertSame('01016943505', $bundle[0]['phone']);
        $this->assertSame('12 Road 9, Maadi', $bundle[0]['address']);
    }

    public function test_another_restaurant_is_never_in_this_till_bundle(): void
    {
        $this->postJson('/api/pos/customers', $this->payload(), $this->deviceHeaders($this->token))
            ->assertCreated();

        $other = Restaurant::factory()->create();
        TenantContext::overrideId($other->id);
        try {
            Customer::forceCreate([
                'restaurant_id' => $other->id,
                'name' => 'Somebody Else',
                'phone' => '01111111111',
            ]);
        } finally {
            TenantContext::clearOverride();
        }

        $bundle = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($this->token))
            ->assertOk()
            ->json('customers');

        $this->assertCount(1, $bundle);
        $this->assertSame('Amer', $bundle[0]['name']);
    }
}
