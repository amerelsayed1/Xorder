<?php

namespace Tests\Feature\Pos;

use App\Enums\RoleEnum;
use App\Models\Branch;
use App\Models\Category;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\PosWaiterDevice;
use App\Models\PosWaiterSession;
use App\Models\Restaurant;
use App\Models\TableCheckDraft;
use App\Models\User;
use App\Support\PosPin;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/**
 * POS-BE-033: the waiter wire served by the platform (XOrder Waiter – Cloud).
 * Routes are /api/pos/waiter/{slug}/v1/…; the tenant is the slug.
 */
class WaiterWireTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Branch $branch;

    private User $waiter;

    private DiningTable $table;

    private MenuItem $coffee;

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('waiter-signin');

        [$this->restaurant, $this->branch, $this->table, $this->coffee, $this->waiter] = $this->seedRestaurant('alpha');
    }

    /** @return array{Restaurant, Branch, DiningTable, MenuItem, User} */
    private function seedRestaurant(string $slug, string $price = '10.00'): array
    {
        $restaurant = Restaurant::factory()->create(['slug' => $slug, 'currency' => 'EGP']);
        $restaurant->features()->create(['feature_key' => 'table_management', 'is_enabled' => true]);

        $branch = new Branch(['name_en' => 'Main']);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        $area = new DiningArea(['branch_id' => $branch->id, 'name_en' => 'Indoor', 'is_active' => true]);
        $area->restaurant_id = $restaurant->id;
        $area->save();

        $table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => '1', 'seats_count' => 4, 'is_active' => true,
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $table->restaurant_id = $restaurant->id;
        $table->branch_id = $branch->id;
        $table->save();

        $category = Category::factory()->create(['restaurant_id' => $restaurant->id, 'is_active' => true]);
        $item = MenuItem::factory()->create([
            'restaurant_id' => $restaurant->id, 'category_id' => $category->id,
            'name_en' => 'Coffee', 'name_ar' => 'قهوة', 'price' => $price,
        ]);

        $pin = PosPin::make('1234');
        $user = User::factory()->restaurantAdmin($restaurant->id)->create([
            'name' => 'Amer', 'username' => 'amer', 'pos_pin_salt' => $pin['salt'], 'pos_pin_hash' => $pin['hash'],
        ]);

        return [$restaurant, $branch, $table, $item, $user];
    }

    private function url(string $path, string $slug = 'alpha'): string
    {
        return "/api/pos/waiter/{$slug}/v1/{$path}";
    }

    /** @return array{device: string, session: string} */
    private function signIn(string $slug = 'alpha', string $username = 'amer'): array
    {
        $res = $this->postJson($this->url('sign-in', $slug), [
            'username' => $username, 'pin' => '1234', 'device_name' => 'Amer · Android',
        ])->assertOk();

        return ['device' => $res->json('device_token'), 'session' => $res->json('session')];
    }

    /** @param array{device: string, session: string} $auth */
    private function headers(array $auth): array
    {
        return ['Authorization' => 'Device '.$auth['device'], 'X-Waiter-Session' => $auth['session']];
    }

    private function ops(array $auth, array $ops, ?int $version = null, ?int $tableId = null, string $slug = 'alpha')
    {
        return $this->postJson(
            $this->url('tables/'.($tableId ?? $this->table->id).'/ops', $slug),
            ['ops' => $ops] + ($version !== null ? ['version' => $version] : []),
            $this->headers($auth),
        );
    }

    // ------------------------------------------------------------ hello / gate

    public function test_hello_names_the_restaurant_without_auth(): void
    {
        $this->getJson($this->url('hello'))
            ->assertOk()
            ->assertJsonPath('wire', 1)
            ->assertJsonPath('name', $this->restaurant->name_en);
    }

    public function test_unknown_slug_is_not_found_in_the_wire_shape(): void
    {
        $this->getJson($this->url('hello', 'nobody'))->assertNotFound()->assertJsonPath('code', 'NOT_FOUND');
    }

    public function test_a_restaurant_without_table_management_is_not_served(): void
    {
        $this->restaurant->features()->where('feature_key', 'table_management')->update(['is_enabled' => false]);

        $this->getJson($this->url('hello'))->assertForbidden()->assertJsonPath('code', 'NOT_PERMITTED');
    }

    // ----------------------------------------------------------------- sign-in

    public function test_first_sign_in_registers_the_device_and_returns_its_token_once(): void
    {
        $first = $this->postJson($this->url('sign-in'), ['username' => 'amer', 'pin' => '1234', 'device_name' => 'Phone A'])
            ->assertOk()
            ->assertJsonPath('staff.id', $this->waiter->id)
            ->assertJsonPath('staff.name', 'Amer');

        $this->assertStringStartsWith('xwd_', $first->json('device_token'));
        $this->assertStringStartsWith('xws_', $first->json('session'));
        $this->assertContains('pos.operate', $first->json('staff.capabilities'));

        $device = PosWaiterDevice::where('restaurant_id', $this->restaurant->id)->sole();
        $this->assertSame('Phone A', $device->name);
        $this->assertNotSame($first->json('device_token'), $device->token_hash, 'the token is stored hashed');

        $again = $this->postJson($this->url('sign-in'), ['username' => 'amer', 'pin' => '1234', 'device_name' => 'Phone A'],
            ['Authorization' => 'Device '.$first->json('device_token')])
            ->assertOk();

        $this->assertArrayNotHasKey('device_token', $again->json());
        $this->assertSame(1, PosWaiterDevice::count());
    }

    public function test_wrong_pin_and_unknown_username_give_one_error(): void
    {
        $this->postJson($this->url('sign-in'), ['username' => 'amer', 'pin' => '0000'])
            ->assertUnauthorized()->assertJsonPath('code', 'PIN_WRONG');
        $this->postJson($this->url('sign-in'), ['username' => 'ghost', 'pin' => '1234'])
            ->assertUnauthorized()->assertJsonPath('code', 'PIN_WRONG');
        $this->assertSame(0, PosWaiterDevice::count());
    }

    public function test_five_failures_lock_the_device_out_for_a_minute(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson($this->url('sign-in'), ['username' => 'amer', 'pin' => '0000'])->assertUnauthorized();
        }

        $this->postJson($this->url('sign-in'), ['username' => 'amer', 'pin' => '1234'])
            ->assertStatus(429)->assertJsonPath('code', 'TOO_MANY_ATTEMPTS');
    }

    public function test_a_waiter_without_pos_operate_cannot_sign_in(): void
    {
        $pin = PosPin::make('4321');
        User::factory()->restaurantAdmin($this->restaurant->id)->create([
            'username' => 'nobody', 'role' => RoleEnum::RESTAURANT_STAFF, 'role_id' => null,
            'pos_pin_salt' => $pin['salt'], 'pos_pin_hash' => $pin['hash'],
        ]);

        $this->postJson($this->url('sign-in'), ['username' => 'nobody', 'pin' => '4321'])
            ->assertForbidden()->assertJsonPath('code', 'NOT_PERMITTED');
        $this->assertSame(0, PosWaiterDevice::count());
    }

    public function test_a_user_with_no_pin_cannot_sign_in(): void
    {
        User::factory()->restaurantAdmin($this->restaurant->id)->create(['username' => 'nopin']);

        $this->postJson($this->url('sign-in'), ['username' => 'nopin', 'pin' => '1234'])
            ->assertUnauthorized()->assertJsonPath('code', 'PIN_WRONG');
    }

    // -------------------------------------------------------- device / session

    public function test_calls_need_a_device_then_a_session(): void
    {
        $this->getJson($this->url('floor'))->assertUnauthorized()->assertJsonPath('code', 'UNPAIRED');

        $auth = $this->signIn();

        $this->getJson($this->url('floor'), ['Authorization' => 'Device '.$auth['device']])
            ->assertUnauthorized()->assertJsonPath('code', 'SIGN_IN_REQUIRED');

        $this->getJson($this->url('floor'), $this->headers($auth))->assertOk();
    }

    public function test_a_revoked_device_is_refused(): void
    {
        $auth = $this->signIn();
        PosWaiterDevice::query()->update(['revoked_at' => now()]);

        $this->getJson($this->url('floor'), $this->headers($auth))
            ->assertForbidden()->assertJsonPath('code', 'DEVICE_REVOKED');
    }

    public function test_a_session_idles_out_after_twelve_hours(): void
    {
        $auth = $this->signIn();
        PosWaiterSession::query()->update(['last_seen_at' => now()->subHours(13)]);

        $this->getJson($this->url('floor'), $this->headers($auth))
            ->assertUnauthorized()->assertJsonPath('code', 'SIGN_IN_REQUIRED');
    }

    public function test_sign_out_ends_the_session(): void
    {
        $auth = $this->signIn();

        $this->postJson($this->url('sign-out'), [], $this->headers($auth))->assertOk();
        $this->getJson($this->url('floor'), $this->headers($auth))
            ->assertUnauthorized()->assertJsonPath('code', 'SIGN_IN_REQUIRED');
    }

    // --------------------------------------------------------- tenant boundary

    public function test_tokens_of_one_restaurant_are_unknown_at_another(): void
    {
        [$beta, , $betaTable, $betaItem] = $this->seedRestaurant('beta');
        $alpha = $this->signIn('alpha');

        // Alpha's credentials against beta's slug.
        $this->getJson($this->url('floor', 'beta'), $this->headers($alpha))
            ->assertUnauthorized()->assertJsonPath('code', 'UNPAIRED');

        // Alpha's session cannot reach a beta table, nor sell a beta product.
        $this->getJson($this->url('tables/'.$betaTable->id.'/check'), $this->headers($alpha))
            ->assertNotFound()->assertJsonPath('code', 'NOT_FOUND');
        $this->ops($alpha, [['op' => 'add', 'product_id' => $betaItem->id, 'qty' => 1]], 0)
            ->assertStatus(422)->assertJsonPath('code', 'REFUSED')->assertJsonPath('reason', 'unknown_product');

        // And beta's floor lists only beta's table.
        $beta = $this->signIn('beta');
        $ids = collect($this->getJson($this->url('floor', 'beta'), $this->headers($beta))->json('tables'))->pluck('id');
        $this->assertSame([$betaTable->id], $ids->all());
    }

    // -------------------------------------------------------------- menu/floor

    public function test_menu_prices_come_from_the_server(): void
    {
        $auth = $this->signIn();

        $menu = $this->getJson($this->url('menu'), $this->headers($auth))->assertOk();
        $menu->assertJsonPath('currency.code', 'EGP')->assertJsonPath('currency.exponent', 2);
        $product = collect($menu->json('products'))->firstWhere('id', $this->coffee->id);
        $this->assertSame(1000, $product['price_minor']);
        $this->assertSame('قهوة', $product['name']['ar']);
        $this->assertCount(1, $menu->json('categories'));
    }

    public function test_floor_shows_a_free_table_then_an_open_one(): void
    {
        $auth = $this->signIn();

        $table = $this->getJson($this->url('floor'), $this->headers($auth))->json('tables.0');
        $this->assertSame('free', $table['state']);
        $this->assertSame(0, $table['total_minor']);

        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 2]], 0)->assertOk();

        $table = $this->getJson($this->url('floor'), $this->headers($auth))->json('tables.0');
        $this->assertSame('open', $table['state']);
        $this->assertSame(2000, $table['total_minor']);
        $this->assertSame(2, $table['items']);
    }

    // ----------------------------------------------------------------- ops

    public function test_a_free_table_has_an_empty_check_at_version_zero(): void
    {
        $auth = $this->signIn();

        $this->getJson($this->url('tables/'.$this->table->id.'/check'), $this->headers($auth))
            ->assertOk()
            ->assertJsonPath('version', 0)
            ->assertJsonPath('lines', [])
            ->assertJsonPath('total_minor', 0);
    }

    public function test_adding_a_line_prices_it_on_the_server_and_ignores_a_client_price(): void
    {
        $auth = $this->signIn();

        $check = $this->ops($auth, [[
            'op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 2,
            // None of these is part of the wire; a hostile client sends them anyway.
            'price_minor' => 1, 'total_minor' => 1, 'unit_price' => 0.01,
        ]], 0)->assertOk();

        $check->assertJsonPath('version', 1)
            ->assertJsonPath('lines.0.stage', 'draft')
            ->assertJsonPath('lines.0.qty', 2)
            ->assertJsonPath('lines.0.total_minor', 2000)
            ->assertJsonPath('subtotal_minor', 2000)
            ->assertJsonPath('total_minor', 2000);
    }

    public function test_the_same_product_merges_into_one_draft_line(): void
    {
        $auth = $this->signIn();

        $check = $this->ops($auth, [
            ['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1],
            ['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 2],
        ], 0)->assertOk();

        $this->assertCount(1, $check->json('lines'));
        $this->assertSame(3, $check->json('lines.0.qty'));
    }

    public function test_qty_note_guests_and_remove_edit_the_draft(): void
    {
        $auth = $this->signIn();
        $key = $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1]], 0)->json('lines.0.key');

        $check = $this->ops($auth, [
            ['op' => 'qty', 'line' => $key, 'delta' => 2],
            ['op' => 'note', 'line' => $key, 'note' => 'no sugar'],
            ['op' => 'guests', 'guests' => 3],
        ], 1)->assertOk();

        $check->assertJsonPath('lines.0.qty', 3)->assertJsonPath('lines.0.note', 'no sugar')
            ->assertJsonPath('guests', 3)->assertJsonPath('version', 2);

        $this->ops($auth, [['op' => 'qty', 'line' => $key, 'delta' => -3]], 2)
            ->assertOk()->assertJsonPath('lines', []);
    }

    public function test_a_stale_version_is_refused_with_the_current_check(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1]], 0)->assertOk();

        // A second phone still holds version 0.
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 5]], 0)
            ->assertStatus(409)
            ->assertJsonPath('code', 'CHECK_CHANGED')
            ->assertJsonPath('check.version', 1)
            ->assertJsonPath('check.lines.0.qty', 1);

        $this->assertSame(1, collect(TableCheckDraft::first()->lines)->sum('qty'), 'the refused batch changed nothing');
    }

    public function test_a_batch_is_all_or_none(): void
    {
        $auth = $this->signIn();

        $this->ops($auth, [
            ['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1],
            ['op' => 'remove', 'line' => 'dnosuchline'],
        ], 0)->assertNotFound();

        $this->getJson($this->url('tables/'.$this->table->id.'/check'), $this->headers($auth))
            ->assertJsonPath('version', 0)->assertJsonPath('lines', []);
    }

    public function test_an_unavailable_product_and_a_bad_quantity_are_refused(): void
    {
        $auth = $this->signIn();
        $this->coffee->forceFill(['is_available' => false])->save();

        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1]], 0)
            ->assertStatus(422)->assertJsonPath('reason', 'unavailable');

        $this->coffee->forceFill(['is_available' => true])->save();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 0]], 0)
            ->assertStatus(422)->assertJsonPath('reason', 'bad_quantity');
    }

    public function test_an_unknown_op_and_an_empty_batch_are_bad_requests(): void
    {
        $auth = $this->signIn();

        $this->ops($auth, [['op' => 'explode']], 0)->assertStatus(400)->assertJsonPath('code', 'BAD_REQUEST');
        $this->ops($auth, [], 0)->assertStatus(400)->assertJsonPath('code', 'BAD_REQUEST');
    }

    // ----------------------------------------------------------------- send

    public function test_send_turns_the_draft_into_a_round_of_the_visits_order(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 2]], 0)->assertOk();

        $check = $this->ops($auth, [['op' => 'send']], 1)->assertOk();

        $check->assertJsonPath('lines.0.stage', 'sent')
            ->assertJsonPath('lines.0.round', 1)
            ->assertJsonPath('rounds_sent', 1)
            ->assertJsonPath('total_minor', 2000)
            ->assertJsonPath('version', 2);

        $order = Order::where('table_id', $this->table->id)->sole();
        $this->assertSame('NEW', $order->status->value);
        $this->assertSame('dine_in', $order->order_type);
        $this->assertSame('waiter', $order->source);
        $this->assertSame(2000, $order->total_minor);
        $this->assertSame(1, $order->rounds()->count());
        $this->assertSame(2, (int) $order->rounds()->first()->items()->sum('quantity'));
        $this->assertSame([], TableCheckDraft::first()->lines, 'the draft is emptied');
    }

    public function test_a_second_round_appends_to_the_same_order(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1], ['op' => 'send']], 0)->assertOk();

        $check = $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 3], ['op' => 'send']], 1)->assertOk();

        $this->assertSame(1, Order::count());
        $check->assertJsonPath('rounds_sent', 2)->assertJsonPath('total_minor', 4000);
        $this->assertSame(['sent', 'sent'], array_column($check->json('lines'), 'stage'));
    }

    public function test_a_repeated_send_is_never_a_second_round(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1]], 0)->assertOk();
        $this->ops($auth, [['op' => 'send']], 1)->assertOk();

        // The phone lost the response and retries the same request.
        $this->ops($auth, [['op' => 'send']], 1)->assertStatus(409)->assertJsonPath('code', 'CHECK_CHANGED');
        $this->assertSame(1, Order::first()->rounds()->count());

        // A fresh read has nothing left to send.
        $this->ops($auth, [['op' => 'send']], 2)->assertStatus(422)->assertJsonPath('reason', 'nothing_to_send');
        $this->assertSame(1, Order::first()->rounds()->count());
    }

    public function test_a_sent_line_cannot_be_edited_from_the_handheld(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1], ['op' => 'send']], 0)->assertOk();
        $key = $this->getJson($this->url('tables/'.$this->table->id.'/check'), $this->headers($auth))->json('lines.0.key');

        $this->ops($auth, [['op' => 'remove', 'line' => $key]], 1)
            ->assertStatus(422)->assertJsonPath('reason', 'line_sent');
        $this->ops($auth, [['op' => 'qty', 'line' => $key, 'delta' => 1]], 1)
            ->assertStatus(422)->assertJsonPath('reason', 'line_sent');
    }

    public function test_a_sent_line_keeps_its_price_when_the_menu_price_changes(): void
    {
        $auth = $this->signIn();
        $this->ops($auth, [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1], ['op' => 'send']], 0)->assertOk();

        $this->coffee->forceFill(['price' => '99.00'])->save();

        $this->getJson($this->url('tables/'.$this->table->id.'/check'), $this->headers($auth))
            ->assertJsonPath('lines.0.total_minor', 1000)->assertJsonPath('total_minor', 1000);
    }

    // -------------------------------------------------------------- dashboard

    public function test_the_dashboard_lists_and_revokes_this_restaurants_waiter_devices(): void
    {
        $this->restaurant->features()->firstOrCreate(['feature_key' => 'table_management'], ['is_enabled' => true]);
        $auth = $this->signIn();
        $device = PosWaiterDevice::sole();

        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-devices')
            ->assertOk()->assertJsonPath('data.0.name', 'Amer · Android')
            ->assertJsonMissingPath('data.0.token_hash');

        $this->actingAs($this->waiter)->postJson("/api/dashboard/waiter-devices/{$device->id}/revoke")
            ->assertOk();

        $this->getJson($this->url('floor'), $this->headers($auth))
            ->assertForbidden()->assertJsonPath('code', 'DEVICE_REVOKED');
        $this->assertSame(0, PosWaiterSession::count());
    }

    public function test_another_restaurant_cannot_see_or_revoke_my_devices(): void
    {
        [, , , , $betaOwner] = $this->seedRestaurant('beta');
        $this->signIn();
        $device = PosWaiterDevice::sole();

        $this->actingAs($betaOwner)->getJson('/api/dashboard/waiter-devices')
            ->assertOk()->assertJsonPath('data', []);
        $this->actingAs($betaOwner)->postJson("/api/dashboard/waiter-devices/{$device->id}/revoke")
            ->assertNotFound();
        $this->assertNull($device->fresh()->revoked_at);
    }

    // ------------------------------------------------------------------ unit

    public function test_pos_pin_verify(): void
    {
        $pin = PosPin::make('1234');

        $this->assertTrue(PosPin::verify('1234', $pin['salt'], $pin['hash']));
        $this->assertFalse(PosPin::verify('1235', $pin['salt'], $pin['hash']));
        $this->assertFalse(PosPin::verify('1234', null, null));
        $this->assertFalse(PosPin::verify('1234', 'not base64!!', $pin['hash']));
    }
}
