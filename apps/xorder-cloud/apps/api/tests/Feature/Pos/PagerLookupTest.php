<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\TenderType;
use Illuminate\Support\Str;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the client types
 * the number on their slip. These tests make real till sales so the invoice
 * numbers are the ones the platform issues (`MAADI-2026-000001`), then look
 * them up the way the join page does.
 */
class PagerLookupTest extends PosTestCase
{
    private MenuItem $burger;

    private TenderType $cash;

    private ?string $deviceToken = null;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => true]);
        $this->restaurant->forceFill(['slug' => 'demo'])->save();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $this->burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id, 'category_id' => $category->id,
            'price' => 100.00, 'discounted_price' => null,
        ]);

        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();
        $this->cash = $cash;
    }

    private function token(): string
    {
        return $this->deviceToken ??= $this->claimTerminal()['token'];
    }

    /** A till sale; returns the stored order (with its real invoice number). */
    private function sell(array $overrides = []): Order
    {
        $res = $this->postJson('/api/pos/orders', array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => now()->toIso8601String(),
            'lines' => [['menu_item_id' => $this->burger->id, 'quantity' => 1, 'name_snapshot' => 'Classic Burger']],
            'payments' => [['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $this->cash->id, 'amount_minor' => 10000]],
        ], $overrides), $this->deviceHeaders($this->token()))->assertCreated();

        return Order::query()->findOrFail($res->json('data.id'));
    }

    private function lookup(string $number, string $slug = 'demo')
    {
        return $this->postJson("/api/public/restaurants/{$slug}/pager-lookup", ['number' => $number]);
    }

    // AC-1
    public function test_the_number_at_the_end_of_the_invoice_number_finds_the_order(): void
    {
        $order = $this->sell();
        $this->assertMatchesRegularExpression('/^MAADI-\d{4}-000001$/', $order->invoice_number);

        foreach (['1', '01', '000001', ' 1 '] as $typed) {
            $res = $this->lookup($typed)->assertOk();
            $res->assertJsonPath('data.state', 'found');
            $this->assertSame($order->fresh()->pickup_token, $res->json('data.tracking_token'), "typed '{$typed}'");
        }

        // The full number as printed, in any case and with spaces for dashes.
        $this->lookup(strtolower(str_replace('-', ' ', $order->invoice_number)))->assertOk();
        $this->lookup($order->invoice_number)->assertOk();
    }

    // The integer tail: 1 is not 11, and 11 is not 1.
    public function test_a_short_number_means_that_number_exactly(): void
    {
        for ($i = 0; $i < 11; $i++) {
            $this->sell();
        }
        $first = Order::query()->where('invoice_number', 'like', '%000001')->firstOrFail();
        $eleventh = Order::query()->where('invoice_number', 'like', '%000011')->firstOrFail();

        $one = $this->lookup('1')->assertOk()->json('data.tracking_token');
        $eleven = $this->lookup('11')->assertOk()->json('data.tracking_token');

        $this->assertNotSame($one, $eleven);
        $this->assertSame($first->fresh()->pickup_token, $one);
        $this->assertSame($eleventh->fresh()->pickup_token, $eleven);
    }

    // AC-2
    public function test_arabic_indic_digits_find_the_same_order(): void
    {
        $order = $this->sell();

        $this->lookup('١')->assertOk()
            ->assertJsonPath('data.tracking_token', $order->fresh()->pickup_token);
    }

    // AC-3
    public function test_an_unknown_number_is_not_found_and_so_is_another_restaurants_order(): void
    {
        $this->sell();

        $this->lookup('99')->assertNotFound()->assertJsonPath('data.state', 'not_found');
        $this->lookup('abc')->assertNotFound();

        $other = Restaurant::factory()->create(['slug' => 'other']);
        $other->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => true]);
        // Restaurant A has an order number 1; restaurant B has none: B's client finds nothing.
        $this->lookup('1', 'other')->assertNotFound();
    }

    // AC-4
    public function test_only_recent_paged_orders_can_be_found(): void
    {
        $old = $this->sell();
        Order::withoutGlobalScopes()->whereKey($old->id)->update(['created_at' => now()->subHours(13)]);
        $this->lookup('1')->assertNotFound();

        // A dine-in order is served to the table, never collected: not paged.
        $this->sell(['order_type' => 'dine_in']);
        $this->lookup('2')->assertNotFound();
    }

    // AC-5, AC-7
    public function test_a_till_order_is_made_pageable_once_and_the_order_number_page_reads_it(): void
    {
        $order = $this->sell();
        $this->assertNull($order->pickup_token);

        $first = $this->lookup('1')->assertOk()->json('data.tracking_token');
        $second = $this->lookup('1')->assertOk()->json('data.tracking_token');
        $this->assertSame($first, $second, 'looking it up again changes nothing');

        $fresh = $order->fresh();
        $this->assertSame('PREPARING', $fresh->pickup_status->value);
        $this->assertSame('1', $fresh->pickup_display_ref);

        // The existing order-number page reads it.
        $this->getJson('/api/public/orders/track/'.$first)
            ->assertOk()
            ->assertJsonPath('data.status', 'PREPARING')
            ->assertJsonPath('data.ref', '1');
    }

    public function test_an_order_that_already_has_a_token_keeps_it(): void
    {
        $order = $this->sell();
        $token = str_repeat('T', 40);
        $order->forceFill(['pickup_token' => $token, 'pickup_status' => 'READY'])->save();

        $this->lookup('1')->assertOk()->assertJsonPath('data.tracking_token', $token);
        $this->assertSame('READY', $order->fresh()->pickup_status->value, 'a lookup never moves an order backwards');
    }

    // AC-6
    public function test_two_branches_with_the_same_number_are_ambiguous_until_the_full_number_is_typed(): void
    {
        $maadi = $this->sell();

        $main = new Branch(['name_en' => 'Main', 'code' => 'MAIN', 'supported_order_types' => ['takeaway']]);
        $main->restaurant_id = $this->restaurant->id;
        $main->save();
        $mainOrder = $this->sell(['branch_id' => $main->id]);
        $this->assertStringStartsWith('MAIN-', $mainOrder->invoice_number);

        $this->lookup('1')->assertStatus(409)->assertJsonPath('data.state', 'ambiguous');

        $this->lookup($mainOrder->invoice_number)->assertOk();
        $this->lookup($maadi->invoice_number)->assertOk();
        $this->assertNotSame(
            $this->lookup($mainOrder->invoice_number)->json('data.tracking_token'),
            $this->lookup($maadi->invoice_number)->json('data.tracking_token'),
        );
    }

    // AC-8
    public function test_it_is_not_available_without_the_feature_or_for_an_unknown_restaurant(): void
    {
        $this->sell();
        $this->restaurant->features()->where('feature_key', 'guest_paging')->update(['is_enabled' => false]);

        $this->lookup('1')->assertForbidden();
        $this->getJson('/api/public/restaurants/demo/pager-lookup')->assertForbidden();
        $this->lookup('1', 'nobody')->assertNotFound();
        $this->getJson('/api/public/restaurants/nobody/pager-lookup')->assertNotFound();
    }

    public function test_the_info_call_gives_the_name_language_and_brand(): void
    {
        $res = $this->getJson('/api/public/restaurants/demo/pager-lookup')->assertOk();

        $this->assertSame(
            ['name', 'name_ar', 'name_en', 'default_language', 'bilingual', 'logo_url', 'brand_color'],
            array_keys($res->json('data.restaurant')),
        );
        $res->assertHeader('Cache-Control', 'no-store, private');
    }

    public function test_a_missing_number_is_a_validation_error(): void
    {
        $this->postJson('/api/public/restaurants/demo/pager-lookup', [])->assertStatus(422);
    }

    // AC-9
    public function test_lookups_are_rate_limited_per_address(): void
    {
        for ($i = 0; $i < 120; $i++) {
            $this->lookup('99')->assertNotFound();
        }

        $this->lookup('99')->assertStatus(429);
    }
}
