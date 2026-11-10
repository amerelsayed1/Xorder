<?php

namespace Tests\Feature\Pos;

use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\Category;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\PosWaiterDevice;
use App\Models\PosWaiterShift;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Support\PosPin;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/**
 * POS-BE-033 shift clock: a waiter starts a shift before working tables and
 * finishes it when leaving. Wire shape matches xorder_waiter_link's
 * `WaiterShift` (`{id, started_at, ended_at?}`, UTC ISO-8601).
 */
class WaiterShiftTest extends TestCase
{
    use RefreshDatabase;

    private const ISO_UTC = '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/';

    private Restaurant $restaurant;

    private DiningTable $table;

    private MenuItem $coffee;

    private User $waiter;

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('waiter-signin');

        [$this->restaurant, $this->table, $this->coffee, $this->waiter] = $this->seedRestaurant('alpha');
    }

    /** @return array{Restaurant, DiningTable, MenuItem, User} */
    private function seedRestaurant(string $slug): array
    {
        $restaurant = Restaurant::factory()->create(['slug' => $slug, 'currency' => 'EGP', 'timezone' => 'UTC']);
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
            'name_en' => 'Coffee', 'name_ar' => 'قهوة', 'price' => '10.00',
        ]);

        $user = $this->waiterAt($restaurant, 'amer', 'Amer');

        return [$restaurant, $table, $item, $user];
    }

    private function waiterAt(Restaurant $restaurant, string $username, string $name): User
    {
        $pin = PosPin::make('1234');

        return User::factory()->restaurantAdmin($restaurant->id)->create([
            'name' => $name, 'username' => $username, 'pos_pin_salt' => $pin['salt'], 'pos_pin_hash' => $pin['hash'],
        ]);
    }

    private function url(string $path, string $slug = 'alpha'): string
    {
        return "/api/pos/waiter/{$slug}/v1/{$path}";
    }

    /** @return array{device: string, session: string, body: array<string, mixed>} */
    private function signIn(string $slug = 'alpha', string $username = 'amer', string $deviceName = 'Phone A', ?string $device = null): array
    {
        $res = $this->postJson(
            $this->url('sign-in', $slug),
            ['username' => $username, 'pin' => '1234', 'device_name' => $deviceName],
            $device !== null ? ['Authorization' => 'Device '.$device] : [],
        )->assertOk();

        return ['device' => $device ?? $res->json('device_token'), 'session' => $res->json('session'), 'body' => $res->json()];
    }

    private function headers(array $auth): array
    {
        return ['Authorization' => 'Device '.$auth['device'], 'X-Waiter-Session' => $auth['session']];
    }

    private function start(array $auth, string $slug = 'alpha')
    {
        return $this->postJson($this->url('shift/start', $slug), [], $this->headers($auth));
    }

    private function finish(array $auth, string $slug = 'alpha')
    {
        return $this->postJson($this->url('shift/finish', $slug), [], $this->headers($auth));
    }

    // ------------------------------------------------------------------ wire

    public function test_start_opens_a_shift_in_the_wire_shape(): void
    {
        $auth = $this->signIn();

        $this->getJson($this->url('shift'), $this->headers($auth))->assertOk()->assertExactJson(['shift' => null]);

        $res = $this->start($auth)->assertOk();
        $shift = $res->json('shift');
        $this->assertSame(['id', 'started_at'], array_keys($shift));
        $this->assertIsInt($shift['id']);
        $this->assertMatchesRegularExpression(self::ISO_UTC, $shift['started_at']);

        $this->getJson($this->url('shift'), $this->headers($auth))->assertOk()->assertExactJson(['shift' => $shift]);

        $row = PosWaiterShift::sole();
        $this->assertSame($this->restaurant->id, $row->restaurant_id);
        $this->assertSame($this->waiter->id, $row->user_id);
        $this->assertSame(PosWaiterDevice::sole()->id, $row->started_device_id);
    }

    public function test_start_is_idempotent_across_devices(): void
    {
        $phoneA = $this->signIn();
        $first = $this->start($phoneA)->assertOk()->json('shift');
        $this->assertSame($first, $this->start($phoneA)->assertOk()->json('shift'));

        // The same waiter on a second phone: still the one shift.
        $phoneB = $this->signIn(deviceName: 'Phone B');
        $this->assertNotSame($phoneA['device'], $phoneB['device']);
        $this->assertSame($first, $this->start($phoneB)->assertOk()->json('shift'));

        $this->assertSame(1, PosWaiterShift::count());
    }

    public function test_the_database_refuses_a_second_open_shift(): void
    {
        $this->start($this->signIn())->assertOk();

        $this->expectException(UniqueConstraintViolationException::class);
        $row = new PosWaiterShift;
        $row->forceFill(['restaurant_id' => $this->restaurant->id, 'user_id' => $this->waiter->id, 'started_at' => now()])->save();
    }

    public function test_finish_closes_the_shift_and_records_the_device(): void
    {
        $phoneA = $this->signIn();
        $this->travelTo(now()->startOfMinute());
        $started = $this->start($phoneA)->json('shift');

        $phoneB = $this->signIn(deviceName: 'Phone B');
        $this->travel(95)->minutes();
        $res = $this->finish($phoneB)->assertOk();

        $shift = $res->json('shift');
        $this->assertSame(['id', 'started_at', 'ended_at'], array_keys($shift));
        $this->assertSame($started['id'], $shift['id']);
        $this->assertSame($started['started_at'], $shift['started_at']);
        $this->assertMatchesRegularExpression(self::ISO_UTC, $shift['ended_at']);

        $row = PosWaiterShift::sole();
        $this->assertSame(95, (int) $row->started_at->diffInMinutes($row->ended_at));
        $this->assertSame(PosWaiterDevice::where('name', 'Phone B')->sole()->id, $row->ended_device_id);

        $this->getJson($this->url('shift'), $this->headers($phoneA))->assertOk()->assertExactJson(['shift' => null]);

        // A new shift can start after the last one finished.
        $this->assertNotSame($started['id'], $this->start($phoneA)->assertOk()->json('shift.id'));
        $this->assertSame(2, PosWaiterShift::count());
    }

    public function test_finish_with_no_open_shift_is_a_conflict(): void
    {
        $auth = $this->signIn();

        $this->finish($auth)->assertStatus(409)->assertJsonPath('code', 'NO_OPEN_SHIFT');

        $this->start($auth)->assertOk();
        $this->finish($auth)->assertOk();
        $this->finish($auth)->assertStatus(409)->assertJsonPath('code', 'NO_OPEN_SHIFT');
    }

    public function test_tables_are_worked_on_the_clock_and_the_menu_is_not(): void
    {
        $auth = $this->signIn();
        $h = $this->headers($auth);
        $ops = ['version' => 0, 'ops' => [['op' => 'add', 'product_id' => $this->coffee->id, 'qty' => 1]]];

        $this->getJson($this->url('floor'), $h)->assertForbidden()->assertJsonPath('code', 'SHIFT_REQUIRED');
        $this->getJson($this->url('tables/'.$this->table->id.'/check'), $h)->assertForbidden()->assertJsonPath('code', 'SHIFT_REQUIRED');
        $this->postJson($this->url('tables/'.$this->table->id.'/ops'), $ops, $h)->assertForbidden()->assertJsonPath('code', 'SHIFT_REQUIRED');

        $this->getJson($this->url('menu'), $h)->assertOk();
        $this->getJson($this->url('hello'))->assertOk();

        $this->start($auth)->assertOk();
        $this->getJson($this->url('floor'), $h)->assertOk();
        $this->getJson($this->url('tables/'.$this->table->id.'/check'), $h)->assertOk();
        $this->postJson($this->url('tables/'.$this->table->id.'/ops'), $ops, $h)->assertOk();

        $this->finish($auth)->assertOk();
        $this->getJson($this->url('floor'), $h)->assertForbidden()->assertJsonPath('code', 'SHIFT_REQUIRED');
    }

    public function test_a_shift_is_the_waiters_not_the_devices(): void
    {
        $this->waiterAt($this->restaurant, 'sara', 'Sara');
        $amer = $this->signIn();
        $this->start($amer)->assertOk();

        // Sara signs in on Amer's phone: Amer's shift does not open her floor.
        $sara = $this->signIn(username: 'sara', device: $amer['device']);
        $this->assertArrayNotHasKey('shift', $sara['body']);
        $this->getJson($this->url('floor'), $this->headers($sara))->assertForbidden()->assertJsonPath('code', 'SHIFT_REQUIRED');
    }

    public function test_sign_in_carries_the_open_shift_and_sign_out_keeps_it(): void
    {
        $first = $this->signIn();
        $this->assertArrayNotHasKey('shift', $first['body']);

        $shift = $this->start($first)->json('shift');
        $this->postJson($this->url('sign-out'), [], $this->headers($first))->assertOk();
        $this->assertNull(PosWaiterShift::sole()->ended_at);

        $again = $this->signIn(device: $first['device']);
        $this->assertSame($shift, $again['body']['shift']);
    }

    public function test_shift_calls_need_a_session(): void
    {
        $auth = $this->signIn();

        $this->postJson($this->url('shift/start'), [], ['Authorization' => 'Device '.$auth['device']])
            ->assertUnauthorized()->assertJsonPath('code', 'SIGN_IN_REQUIRED');
        $this->assertSame(0, PosWaiterShift::count());
    }

    public function test_one_restaurants_session_cannot_clock_in_at_another(): void
    {
        $this->seedRestaurant('beta');
        $alpha = $this->signIn();

        $this->postJson($this->url('shift/start', 'beta'), [], $this->headers($alpha))
            ->assertUnauthorized()->assertJsonPath('code', 'UNPAIRED');
        $this->assertSame(0, PosWaiterShift::count());
    }

    // ------------------------------------------------------------- dashboard

    public function test_the_dashboard_lists_shifts_with_durations_devices_and_totals(): void
    {
        $this->travelTo(now()->setTime(9, 0));
        $auth = $this->signIn();
        $this->start($auth);
        $this->travel(90)->minutes();
        $this->finish($auth);
        $this->travel(30)->minutes();
        $this->start($auth);
        $this->travel(15)->minutes();

        $res = $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts')->assertOk();

        $res->assertJsonPath('meta.total', 2)
            // The open shift sorts first and runs to now.
            ->assertJsonPath('data.0.open', true)
            ->assertJsonPath('data.0.ended_at', null)
            ->assertJsonPath('data.0.duration_minutes', 15)
            ->assertJsonPath('data.0.waiter_name', 'Amer')
            ->assertJsonPath('data.0.started_device', 'Phone A')
            ->assertJsonPath('data.1.open', false)
            ->assertJsonPath('data.1.duration_minutes', 90)
            ->assertJsonPath('data.1.ended_device', 'Phone A')
            ->assertJsonPath('totals.0.user_id', $this->waiter->id)
            ->assertJsonPath('totals.0.waiter_name', 'Amer')
            ->assertJsonPath('totals.0.shifts', 2)
            ->assertJsonPath('totals.0.minutes', 105)
            ->assertJsonPath('totals.0.on_shift', true)
            ->assertJsonPath('waiters.0.name', 'Amer');
    }

    public function test_the_dashboard_filters_by_range_and_waiter(): void
    {
        $sara = $this->waiterAt($this->restaurant, 'sara', 'Sara');
        $this->travelTo(now()->setDate(2026, 11, 1)->setTime(10, 0));
        $amer = $this->signIn();
        $this->start($amer);
        $this->travel(60)->minutes();
        $this->finish($amer);

        $this->travelTo(now()->setDate(2026, 11, 5)->setTime(10, 0));
        // Four days later the session has idled out: sign in again.
        $amer = $this->signIn(device: $amer['device']);
        $this->start($amer)->assertOk();
        $saraAuth = $this->signIn(username: 'sara', deviceName: 'Phone S');
        $this->start($saraAuth)->assertOk();

        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts?from=2026-11-01&to=2026-11-01')
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.duration_minutes', 60);

        // An open shift overlaps every day after it started.
        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts?from=2026-11-05&to=2026-11-05&user_id='.$sara->id)
            ->assertOk()->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.waiter_name', 'Sara');

        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts?from=2026-11-01&to=2026-11-05')
            ->assertOk()->assertJsonPath('meta.total', 3)->assertJsonCount(2, 'totals');

        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts?from=2026-11-05&to=2026-11-01')
            ->assertStatus(422);
    }

    public function test_another_restaurant_cannot_see_my_shifts(): void
    {
        [, , , $betaOwner] = $this->seedRestaurant('beta');
        $this->start($this->signIn())->assertOk();

        $this->actingAs($betaOwner)->getJson('/api/dashboard/waiter-shifts')
            ->assertOk()->assertJsonPath('data', [])->assertJsonPath('totals', [])->assertJsonPath('waiters', []);
        $this->actingAs($betaOwner)->getJson('/api/dashboard/waiter-shifts?user_id='.$this->waiter->id)
            ->assertOk()->assertJsonPath('meta.total', 0);
    }

    public function test_the_listing_needs_staff_view_and_table_management(): void
    {
        $role = new Role(['name' => 'Floor']);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => TenantCapability::expand(['tables.view', 'pos.operate']),
            'is_system' => false,
        ])->save();
        $floorOnly = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($floorOnly)->getJson('/api/dashboard/waiter-shifts')->assertForbidden();

        $role->forceFill(['capabilities' => TenantCapability::expand(['staff.view'])])->save();
        $this->actingAs($floorOnly->fresh())->getJson('/api/dashboard/waiter-shifts')->assertOk();

        $this->restaurant->features()->where('feature_key', 'table_management')->update(['is_enabled' => false]);
        $this->actingAs($this->waiter)->getJson('/api/dashboard/waiter-shifts')->assertForbidden();
    }
}
