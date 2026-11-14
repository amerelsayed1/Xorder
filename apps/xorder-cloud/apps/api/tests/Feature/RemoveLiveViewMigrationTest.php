<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\Role;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/** live-board-to-pos D9/D11: the data migration that retires `live.view`. */
class RemoveLiveViewMigrationTest extends TestCase
{
    use RefreshDatabase;

    private function role(Restaurant $r, string $name, array $caps): int
    {
        $role = new Role(['name' => $name]);
        $role->forceFill(['restaurant_id' => $r->id, 'capabilities' => $caps, 'is_system' => false])->save();

        return $role->id;
    }

    private function caps(int $id): array
    {
        return json_decode(DB::table('roles')->where('id', $id)->value('capabilities'), true);
    }

    public function test_removes_live_view_keeps_the_rest_and_logs_roles_that_lose_order_access(): void
    {
        $r = Restaurant::factory()->create();
        $onlyLive = $this->role($r, 'Floor', ['live.view']);
        $liveAndOrders = $this->role($r, 'Waiter', ['live.view', 'orders.view', 'menu.view']);
        $untouched = $this->role($r, 'Cook', ['menu.view']);

        Log::spy();

        (include database_path('migrations/2026_11_10_000100_remove_live_view_from_roles.php'))->up();

        $this->assertSame([], $this->caps($onlyLive));
        $this->assertSame(['orders.view', 'menu.view'], $this->caps($liveAndOrders));
        $this->assertSame(['menu.view'], $this->caps($untouched));

        // Only the role left with no order or bill access is reported.
        Log::shouldHaveReceived('warning')->once()->withArgs(fn ($m, $ctx) => $ctx['role_id'] === $onlyLive
            && $ctx['restaurant_id'] === $r->id);
    }

    public function test_is_safe_to_run_twice(): void
    {
        $r = Restaurant::factory()->create();
        $id = $this->role($r, 'Waiter', ['live.view', 'orders.view']);
        $migration = include database_path('migrations/2026_11_10_000100_remove_live_view_from_roles.php');

        $migration->up();
        $migration->up();

        $this->assertSame(['orders.view'], $this->caps($id));
    }
}
