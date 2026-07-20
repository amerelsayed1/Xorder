<?php

namespace Tests\Feature;

use App\Enums\BillRequestStatus;
use App\Enums\RestaurantStatus;
use App\Models\BillRequest;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\TestCase;

class BillRequestTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private Branch $branch;

    private DiningArea $area;

    private DiningTable $table;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'billery']);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->enableBillRequests();

        $this->branch = new Branch(['name_en' => 'Main']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();

        $this->area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Indoor']);
        $this->area->restaurant_id = $this->restaurant->id;
        $this->area->save();

        $this->table = $this->makeTable('12');
    }

    private function enableBillRequests(): void
    {
        $this->restaurant->features()->create(['feature_key' => 'table_management', 'is_enabled' => true]);
        $this->restaurant->features()->create(['feature_key' => 'bill_requests', 'is_enabled' => true]);
        $this->restaurant->load('features');
    }

    private function makeTable(string $label): DiningTable
    {
        $t = new DiningTable([
            'dining_area_id' => $this->area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'is_active' => true,
            'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $this->restaurant->id;
        $t->branch_id = $this->branch->id;
        $t->save();

        return $t;
    }

    private function makeSession(): MenuSession
    {
        $s = new MenuSession([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'table_id' => $this->table->id,
            'language' => 'en',
            'session_token' => Str::random(40),
            'started_at' => now(),
            'last_activity_at' => now(),
            'expires_at' => now()->addHours(2),
        ]);
        $s->restaurant_id = $this->restaurant->id;
        $s->save();

        return $s;
    }

    // AC-004 — customer creates a bill request from their table session.
    public function test_public_create_returns_requested(): void
    {
        $session = $this->makeSession();

        $res = $this->postJson("/api/public/sessions/{$session->session_token}/bill-requests", [])
            ->assertCreated()
            ->assertJsonPath('data.status', BillRequestStatus::REQUESTED->value)
            ->assertJsonStructure(['data' => ['token', 'status']]);

        $this->assertDatabaseHas('bill_requests', [
            'menu_session_id' => $session->id,
            'restaurant_id' => $this->restaurant->id,
            'status' => BillRequestStatus::REQUESTED->value,
        ]);
        $this->assertNotEmpty($res->json('data.token'));
    }

    // AC-005 — re-requesting while one is open surfaces the existing one, no duplicate row.
    public function test_re_request_while_open_returns_duplicate(): void
    {
        $session = $this->makeSession();

        $this->postJson("/api/public/sessions/{$session->session_token}/bill-requests", [])->assertCreated();

        $this->postJson("/api/public/sessions/{$session->session_token}/bill-requests", [])
            ->assertOk()
            ->assertJsonPath('duplicate', true);

        $this->assertSame(1, BillRequest::withoutGlobalScopes()->where('menu_session_id', $session->id)->count());
    }

    public function test_cancel_while_requested_then_blocked_after_seen(): void
    {
        $session = $this->makeSession();
        $token = $this->postJson("/api/public/sessions/{$session->session_token}/bill-requests", [])
            ->assertCreated()->json('data.token');

        // Cancel while still REQUESTED is allowed.
        $this->patchJson("/api/public/bill-requests/{$token}/cancel")
            ->assertOk()
            ->assertJsonPath('data.status', BillRequestStatus::CANCELLED->value);

        // A second request (after cooldown) advanced to SEEN can no longer be cancelled.
        $bill = new BillRequest([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'table_id' => $this->table->id,
            'menu_session_id' => $session->id,
            'public_token' => BillRequest::generateToken(),
            'status' => BillRequestStatus::SEEN->value,
            'requested_at' => now(),
            'seen_at' => now(),
        ]);
        $bill->restaurant_id = $this->restaurant->id;
        $bill->save();

        $this->patchJson("/api/public/bill-requests/{$bill->public_token}/cancel")
            ->assertStatus(422);
    }

    public function test_public_create_forbidden_without_feature(): void
    {
        $this->restaurant->features()->where('feature_key', 'bill_requests')->update(['is_enabled' => false]);
        $session = $this->makeSession();

        $this->postJson("/api/public/sessions/{$session->session_token}/bill-requests", [])
            ->assertStatus(403);
    }

    public function test_dashboard_lists_open_requests_oldest_first(): void
    {
        $this->makeBill(BillRequestStatus::REQUESTED, requestedAt: now()->subMinutes(3));
        $this->makeBill(BillRequestStatus::COMPLETED, requestedAt: now()->subMinutes(10));
        $older = $this->makeBill(BillRequestStatus::SEEN, requestedAt: now()->subMinutes(8));

        $res = $this->actingAs($this->admin)->getJson('/api/dashboard/bill-requests')
            ->assertOk()
            ->assertJsonCount(2, 'data');

        // Oldest open request first.
        $this->assertSame($older->id, $res->json('data.0.id'));
        // Elapsed time is a positive whole number of seconds.
        $this->assertGreaterThan(0, $res->json('data.0.elapsed_seconds'));
    }

    // AC-007 — advancing status stamps the lifecycle columns + actor.
    public function test_dashboard_update_status_stamps_columns(): void
    {
        $bill = $this->makeBill(BillRequestStatus::REQUESTED);

        $this->actingAs($this->admin)->patchJson("/api/dashboard/bill-requests/{$bill->id}/status", [
            'status' => BillRequestStatus::SEEN->value,
        ])->assertOk()->assertJsonPath('data.status', BillRequestStatus::SEEN->value);

        $bill->refresh();
        $this->assertNotNull($bill->seen_at);
        $this->assertSame($this->admin->id, $bill->seen_by);

        $this->actingAs($this->admin)->patchJson("/api/dashboard/bill-requests/{$bill->id}/status", [
            'status' => BillRequestStatus::COMPLETED->value,
        ])->assertOk();

        $bill->refresh();
        $this->assertNotNull($bill->completed_at);
        $this->assertSame($this->admin->id, $bill->completed_by);
    }

    public function test_dashboard_new_count_returns_requested_total(): void
    {
        $this->makeBill(BillRequestStatus::REQUESTED);
        $this->makeBill(BillRequestStatus::REQUESTED);
        $this->makeBill(BillRequestStatus::SEEN);

        $this->actingAs($this->admin)->getJson('/api/dashboard/bill-requests/new-count')
            ->assertOk()
            ->assertJsonPath('count', 2);
    }

    public function test_dashboard_endpoints_forbidden_without_feature(): void
    {
        $this->restaurant->features()->where('feature_key', 'bill_requests')->update(['is_enabled' => false]);

        $this->actingAs($this->admin)->getJson('/api/dashboard/bill-requests')->assertStatus(403);
        $this->actingAs($this->admin)->getJson('/api/dashboard/bill-requests/new-count')->assertStatus(403);

        $bill = $this->makeBill(BillRequestStatus::REQUESTED);
        $this->actingAs($this->admin)->patchJson("/api/dashboard/bill-requests/{$bill->id}/status", [
            'status' => BillRequestStatus::SEEN->value,
        ])->assertStatus(403);
    }

    private function makeBill(BillRequestStatus $status, ?Carbon $requestedAt = null): BillRequest
    {
        $bill = new BillRequest([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $this->area->id,
            'table_id' => $this->table->id,
            'public_token' => BillRequest::generateToken(),
            'status' => $status->value,
            'requested_at' => $requestedAt ?? now(),
        ]);
        $bill->restaurant_id = $this->restaurant->id;
        $bill->save();

        return $bill;
    }
}
