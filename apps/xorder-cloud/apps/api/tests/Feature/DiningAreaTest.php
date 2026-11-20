<?php

namespace Tests\Feature;

use App\Enums\BillRequestStatus;
use App\Models\BillRequest;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DiningAreaTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private Branch $branch;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create();
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->branch = $this->makeBranch($this->restaurant);
    }

    private function makeBranch(Restaurant $r, string $name = 'Main'): Branch
    {
        $b = new Branch(['name_en' => $name]);
        $b->restaurant_id = $r->id;
        $b->save();

        return $b;
    }

    private function enableTables(): void
    {
        $this->restaurant->features()->create(['feature_key' => 'table_management', 'is_enabled' => true]);
    }

    public function test_area_endpoints_require_the_table_management_feature(): void
    {
        $this->actingAs($this->admin)
            ->getJson('/api/dashboard/dining-areas')
            ->assertForbidden();
    }

    public function test_admin_creates_and_lists_dining_area(): void
    {
        $this->enableTables();

        $this->actingAs($this->admin)->postJson('/api/dashboard/dining-areas', [
            'branch_id' => $this->branch->id,
            'name_en' => 'Outdoor', 'type' => 'outdoor',
        ])->assertCreated()->assertJsonPath('data.name_en', 'Outdoor');

        $this->actingAs($this->admin)->getJson('/api/dashboard/dining-areas')
            ->assertOk()
            ->assertJsonPath('data.0.type', 'outdoor')
            ->assertJsonPath('data.0.tables_count', 0);
    }

    public function test_area_requires_a_name_in_one_language(): void
    {
        $this->enableTables();

        $this->actingAs($this->admin)->postJson('/api/dashboard/dining-areas', [
            'branch_id' => $this->branch->id,
        ])->assertStatus(422)->assertJsonValidationErrors('name_en');
    }

    public function test_area_branch_must_belong_to_the_restaurant(): void
    {
        $this->enableTables();
        $otherBranch = $this->makeBranch(Restaurant::factory()->create(), 'Foreign');

        $this->actingAs($this->admin)->postJson('/api/dashboard/dining-areas', [
            'branch_id' => $otherBranch->id, 'name_en' => 'X',
        ])->assertStatus(422)->assertJsonValidationErrors('branch_id');
    }

    public function test_admin_can_disable_an_area(): void
    {
        $this->enableTables();
        $area = $this->makeArea();

        $this->actingAs($this->admin)->patchJson("/api/dashboard/dining-areas/{$area->id}/status", ['is_active' => false])
            ->assertOk()->assertJsonPath('data.is_active', false);
    }

    public function test_area_with_history_cannot_be_deleted(): void
    {
        $this->enableTables();
        $area = $this->makeArea();

        $order = new Order(['status' => 'NEW', 'items' => [], 'total' => 0, 'currency' => 'EGP', 'dining_area_id' => $area->id]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $this->actingAs($this->admin)->deleteJson("/api/dashboard/dining-areas/{$area->id}")
            ->assertStatus(409);

        $this->assertDatabaseHas('dining_areas', ['id' => $area->id]);
    }

    private function makeTableIn(DiningArea $area, string $label): DiningTable
    {
        $t = new DiningTable([
            'dining_area_id' => $area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $area->restaurant_id;
        $t->branch_id = $area->branch_id;
        $t->save();

        return $t;
    }

    private function makeBill(DiningTable $table, BillRequestStatus $status): BillRequest
    {
        $bill = new BillRequest([
            'table_id' => $table->id, 'public_token' => BillRequest::generateToken(),
            'status' => $status, 'requested_at' => now(),
        ]);
        $bill->restaurant_id = $table->restaurant_id;
        $bill->save();

        return $bill;
    }

    public function test_deleting_an_area_cancels_the_open_bill_requests_of_its_tables(): void
    {
        $this->enableTables();
        $area = $this->makeArea();
        $keep = $this->makeArea();
        [$a, $b] = [$this->makeTableIn($area, 'A1'), $this->makeTableIn($area, 'A2')];
        $elsewhere = $this->makeTableIn($keep, 'K1');

        $openA = $this->makeBill($a, BillRequestStatus::REQUESTED);
        $openB = $this->makeBill($b, BillRequestStatus::IN_PROGRESS);
        $done = $this->makeBill($a, BillRequestStatus::COMPLETED);
        $kept = $this->makeBill($elsewhere, BillRequestStatus::REQUESTED);

        $alert = new Notification([
            'type' => 'bill_request.created', 'title' => 'Bill request', 'body' => 'Table wants the bill',
            'data' => ['bill_request_id' => (string) $openA->id, 'url' => '/admin/requests'],
        ]);
        $alert->restaurant_id = $this->restaurant->id;
        $alert->save();

        $this->actingAs($this->admin)->deleteJson("/api/dashboard/dining-areas/{$area->id}")->assertOk();

        $this->assertDatabaseMissing('dining_areas', ['id' => $area->id]);
        foreach ([$openA, $openB] as $bill) {
            $fresh = BillRequest::withoutGlobalScopes()->find($bill->id);
            $this->assertSame(BillRequestStatus::CANCELLED, $fresh->status);
            $this->assertNotNull($fresh->cancelled_at);
        }
        $this->assertSame(BillRequestStatus::COMPLETED, BillRequest::withoutGlobalScopes()->find($done->id)->status);
        $this->assertNotNull($alert->fresh()->read_at);
        // A table in another area keeps its live request.
        $this->assertSame(BillRequestStatus::REQUESTED, BillRequest::withoutGlobalScopes()->find($kept->id)->status);
    }

    public function test_an_area_with_history_that_cannot_be_deleted_keeps_its_open_bill_requests(): void
    {
        $this->enableTables();
        $area = $this->makeArea();
        $bill = $this->makeBill($this->makeTableIn($area, 'H1'), BillRequestStatus::REQUESTED);

        $order = new Order(['status' => 'NEW', 'items' => [], 'total' => 0, 'currency' => 'EGP', 'dining_area_id' => $area->id]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $this->actingAs($this->admin)->deleteJson("/api/dashboard/dining-areas/{$area->id}")->assertStatus(409);

        $this->assertSame(BillRequestStatus::REQUESTED, BillRequest::withoutGlobalScopes()->find($bill->id)->status);
    }

    private function makeArea(): DiningArea
    {
        $a = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Indoor', 'type' => 'indoor']);
        $a->restaurant_id = $this->restaurant->id;
        $a->save();

        return $a;
    }
}
