<?php

namespace Tests\Feature\Pos;

use App\Enums\TenantCapability;
use App\Models\Category;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * XORD-048: the dashboard's order sheet carries what the cashier's receipt
 * carried — invoice number, till, cashier, table, the money breakdown and each
 * payment — from the stored order, on the details request only.
 */
class OrderReceiptSheetTest extends PosTestCase
{
    private DiningTable $table;

    private function tender(string $name, string $kind): TenderType
    {
        $t = new TenderType(['name' => $name, 'kind' => $kind]);
        $t->restaurant_id = $this->restaurant->id;
        $t->save();

        return $t;
    }

    /** A dine-in sale at table T3 (Terrace), paid 120 cash + 80 card. */
    private function ringUpATableSale(): int
    {
        $area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Terrace', 'name_ar' => 'التراس', 'is_active' => true]);
        $area->restaurant_id = $this->restaurant->id;
        $area->save();
        $this->table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => 'T3',
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $this->table->restaurant_id = $this->restaurant->id;
        $this->table->branch_id = $this->branch->id;
        $this->table->save();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00,
            'discounted_price' => null,
        ]);
        $cash = $this->tender('Cash', 'cash');
        $card = $this->tender('Visa', 'card');

        $token = $this->claimTerminal()['token'];

        return $this->postJson('/api/pos/orders', [
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'dine_in',
            'table_id' => $this->table->id,
            'acting_user_id' => $this->owner->id,
            'created_at' => '2026-11-07T10:24:00+02:00',
            'lines' => [['menu_item_id' => $burger->id, 'quantity' => 2, 'name_snapshot' => 'Classic Burger']],
            'payments' => [
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $cash->id, 'amount_minor' => 12000],
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $card->id, 'amount_minor' => 8000],
            ],
        ], $this->deviceHeaders($token))->assertCreated()->json('data.id');
    }

    public function test_a_till_sale_shows_what_its_receipt_carried(): void
    {
        $id = $this->ringUpATableSale();
        $stored = Order::withoutGlobalScopes()->findOrFail($id);
        $this->app['auth']->forgetGuards();

        $data = $this->actingAs($this->owner)->getJson("/api/dashboard/orders/{$id}")
            ->assertOk()
            ->json('data');

        $this->assertNotEmpty($stored->invoice_number);
        $this->assertSame($stored->invoice_number, $data['invoice_number']);
        $this->assertSame('Till 1', $data['terminal_name']);
        $this->assertSame($this->owner->name, $data['cashier_name']);
        $this->assertSame('T3', $data['table_label']);
        $this->assertSame(['name_ar' => 'التراس', 'name_en' => 'Terrace'], $data['dining_area']);
        foreach (['subtotal_minor', 'discount_minor', 'charges_minor', 'tax_minor', 'total_minor', 'refunded_minor'] as $k) {
            $this->assertSame($stored->{$k}, $data[$k], $k);
        }
        $this->assertSame(20000, $data['subtotal_minor']);
        $this->assertSame([
            ['Cash', 'cash', 12000],
            ['Visa', 'card', 8000],
        ], array_map(fn ($p) => [$p['tender_name'], $p['tender_kind'], $p['amount_minor']], $data['payments']));
    }

    public function test_a_diner_order_shows_no_till_cashier_or_payment(): void
    {
        $order = new Order([
            'status' => 'NEW', 'items' => [['name' => 'Tea', 'qty' => 1, 'line_total' => 20]],
            'total' => 20, 'currency' => 'EGP', 'customer_name' => 'Guest', 'source' => 'web',
            'order_type' => 'pickup', 'branch_id' => $this->branch->id,
        ]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $data = $this->actingAs($this->owner)->getJson("/api/dashboard/orders/{$order->id}")
            ->assertOk()
            ->json('data');

        foreach (['invoice_number', 'terminal_name', 'cashier_name', 'table_label', 'dining_area', 'subtotal_minor', 'tax_minor'] as $k) {
            $this->assertArrayHasKey($k, $data);
            $this->assertNull($data[$k], $k);
        }
        $this->assertSame([], $data['payments']);
        $this->assertSame('Guest', $data['customer_name']);
    }

    public function test_another_restaurants_order_is_not_found(): void
    {
        $other = Restaurant::factory()->create();
        $theirs = new Order(['status' => 'NEW', 'items' => [], 'total' => 5, 'currency' => 'EGP', 'source' => 'web']);
        $theirs->restaurant_id = $other->id;
        $theirs->save();

        $this->actingAs($this->owner)->getJson("/api/dashboard/orders/{$theirs->id}")->assertNotFound();
    }

    public function test_staff_need_order_access_to_open_the_sheet(): void
    {
        $order = new Order(['status' => 'NEW', 'items' => [], 'total' => 5, 'currency' => 'EGP', 'source' => 'web']);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $staff = fn (array $caps) => User::factory()->staff($this->restaurant->id, tap(new Role(['name' => 'R'.count($caps)]), fn ($r) => $r->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => TenantCapability::expand($caps),
        ])->save())->id)->create();

        $this->actingAs($staff([]))->getJson("/api/dashboard/orders/{$order->id}")->assertForbidden();
        $this->actingAs($staff(['orders.view']))->getJson("/api/dashboard/orders/{$order->id}")->assertOk();
        $this->app['auth']->forgetGuards();
        $this->getJson("/api/dashboard/orders/{$order->id}")->assertUnauthorized();
    }

    public function test_the_list_is_unchanged_and_the_sheet_keeps_every_list_key(): void
    {
        $id = $this->ringUpATableSale();
        $this->app['auth']->forgetGuards();

        $row = $this->actingAs($this->owner)->getJson('/api/dashboard/orders')->assertOk()->json('data.0');
        $sheet = $this->actingAs($this->owner)->getJson("/api/dashboard/orders/{$id}")->assertOk()->json('data');

        // The table shows on the list row too (XORD-048) …
        $this->assertSame('T3', $row['table_label']);
        // … but the list loads no payments and carries none of the sheet's fields.
        foreach (['payments', 'invoice_number', 'terminal_name', 'cashier_name', 'subtotal_minor'] as $k) {
            $this->assertArrayNotHasKey($k, $row, $k);
        }
        // Additive: every key the list has, the sheet has, with the same value.
        foreach ($row as $k => $v) {
            $this->assertArrayHasKey($k, $sheet, $k);
            $this->assertSame($v, $sheet[$k], $k);
        }
    }
}
