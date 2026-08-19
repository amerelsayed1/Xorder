<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TableTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    private Branch $branch;

    private DiningArea $area;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create();
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->restaurant->features()->create(['feature_key' => 'table_management', 'is_enabled' => true]);

        $this->branch = new Branch(['name_en' => 'Main']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();

        $this->area = $this->makeArea('Indoor');
    }

    private function makeArea(string $name, bool $active = true): DiningArea
    {
        $a = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => $name, 'is_active' => $active]);
        $a->restaurant_id = $this->restaurant->id;
        $a->save();

        return $a;
    }

    public function test_creating_a_table_issues_a_token_and_stamps_qr_time(): void
    {
        $res = $this->actingAs($this->admin)->postJson('/api/dashboard/tables', [
            'dining_area_id' => $this->area->id, 'label' => '12', 'seats_count' => 4,
        ])->assertCreated();

        $id = $res->json('data.id');
        $table = DiningTable::find($id);
        $this->assertNotEmpty($table->public_token);
        $this->assertNotNull($table->qr_generated_at);
        // Branch is derived from the area.
        $this->assertSame($this->branch->id, $table->branch_id);
    }

    public function test_label_must_be_unique_within_an_area_but_may_repeat_across_areas(): void
    {
        $other = $this->makeArea('Outdoor');

        $this->actingAs($this->admin)->postJson('/api/dashboard/tables', [
            'dining_area_id' => $this->area->id, 'label' => '5',
        ])->assertCreated();

        // Same label, same area → rejected.
        $this->actingAs($this->admin)->postJson('/api/dashboard/tables', [
            'dining_area_id' => $this->area->id, 'label' => '5',
        ])->assertStatus(422)->assertJsonValidationErrors('label');

        // Same label, different area → allowed.
        $this->actingAs($this->admin)->postJson('/api/dashboard/tables', [
            'dining_area_id' => $other->id, 'label' => '5',
        ])->assertCreated();
    }

    public function test_disabled_area_is_not_selectable_for_new_tables(): void
    {
        $disabled = $this->makeArea('Closed', active: false);

        $this->actingAs($this->admin)->postJson('/api/dashboard/tables', [
            'dining_area_id' => $disabled->id, 'label' => '1',
        ])->assertStatus(422)->assertJsonValidationErrors('dining_area_id');
    }

    public function test_index_filters_by_area_and_status(): void
    {
        $t = $this->makeTable('A1');
        $this->makeTable('B2', $this->makeArea('Outdoor'));

        $this->actingAs($this->admin)->getJson("/api/dashboard/tables?dining_area_id={$this->area->id}")
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.label', 'A1');

        $t->update(['is_active' => false]);
        $this->actingAs($this->admin)->getJson('/api/dashboard/tables?status=inactive')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.label', 'A1');
    }

    public function test_regenerate_changes_the_token(): void
    {
        $table = $this->makeTable('9');
        $old = $table->public_token;

        $this->actingAs($this->admin)->postJson("/api/dashboard/tables/{$table->id}/qr/regenerate")
            ->assertOk();

        $this->assertNotSame($old, $table->fresh()->public_token);
    }

    public function test_qr_endpoint_returns_svg_and_url(): void
    {
        $table = $this->makeTable('7');

        $this->actingAs($this->admin)->getJson("/api/dashboard/tables/{$table->id}/qr")
            ->assertOk()
            ->assertJsonPath('data.public_token', $table->public_token)
            ->assertJsonStructure(['data' => ['svg', 'url']]);
    }

    public function test_single_table_qr_downloads_as_a_png(): void
    {
        $table = $this->makeTable('7');

        $res = $this->actingAs($this->admin)
            ->get("/api/dashboard/tables/{$table->id}/qr/download")
            ->assertOk();

        $res->assertHeader('Content-Type', 'image/png');

        ob_start();
        $res->baseResponse->sendContent();
        $this->assertStringStartsWith("\x89PNG", ob_get_clean());
    }

    public function test_bulk_qr_download_returns_a_zip_of_selected_tables(): void
    {
        $a = $this->makeTable('1');
        $b = $this->makeTable('2');
        $this->makeTable('3'); // not selected — must be excluded

        $res = $this->actingAs($this->admin)
            ->post('/api/dashboard/tables/qr/download-bulk', ['ids' => [$a->id, $b->id]]);

        $res->assertOk();
        $res->assertHeader('content-type', 'application/zip');

        $tmp = tempnam(sys_get_temp_dir(), 'qrtest-').'.zip';
        file_put_contents($tmp, $res->streamedContent());
        $zip = new \ZipArchive;
        $zip->open($tmp);
        $this->assertSame(2, $zip->numFiles);
        $names = [];
        for ($i = 0; $i < $zip->numFiles; $i++) {
            $names[] = $zip->getNameIndex($i);
        }
        $zip->close();
        unlink($tmp);

        $this->assertContains("qr-1-{$a->public_token}.png", $names);
        $this->assertContains("qr-2-{$b->public_token}.png", $names);
    }

    public function test_bulk_qr_download_ignores_tables_from_other_restaurants(): void
    {
        $mine = $this->makeTable('1');

        $other = Restaurant::factory()->create();
        $otherBranch = new Branch(['name_en' => 'Other']);
        $otherBranch->restaurant_id = $other->id;
        $otherBranch->save();
        $otherArea = new DiningArea(['branch_id' => $otherBranch->id, 'name_en' => 'X', 'is_active' => true]);
        $otherArea->restaurant_id = $other->id;
        $otherArea->save();
        $theirs = new DiningTable([
            'dining_area_id' => $otherArea->id, 'label' => '9',
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $theirs->restaurant_id = $other->id;
        $theirs->branch_id = $otherBranch->id;
        $theirs->save();

        $res = $this->actingAs($this->admin)
            ->post('/api/dashboard/tables/qr/download-bulk', ['ids' => [$mine->id, $theirs->id]]);

        $res->assertOk();
        $tmp = tempnam(sys_get_temp_dir(), 'qrtest-').'.zip';
        file_put_contents($tmp, $res->streamedContent());
        $zip = new \ZipArchive;
        $zip->open($tmp);
        // Only the caller's own table survives the tenant scope.
        $this->assertSame(1, $zip->numFiles);
        $zip->close();
        unlink($tmp);
    }

    public function test_bulk_qr_download_requires_at_least_one_id(): void
    {
        $this->actingAs($this->admin)
            ->postJson('/api/dashboard/tables/qr/download-bulk', ['ids' => []])
            ->assertStatus(422);
    }

    public function test_table_with_orders_cannot_be_deleted(): void
    {
        $table = $this->makeTable('3');
        $order = new Order(['status' => 'NEW', 'items' => [], 'total' => 0, 'currency' => 'EGP', 'table_id' => $table->id]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $this->actingAs($this->admin)->deleteJson("/api/dashboard/tables/{$table->id}")
            ->assertStatus(409);
    }

    public function test_live_board_reflects_occupancy_and_flags_new_orders(): void
    {
        $table = $this->makeTable('L1');
        // No session, no active orders → available, not flashing.
        $this->actingAs($this->admin)->getJson('/api/dashboard/tables/live')
            ->assertOk()
            ->assertJsonPath('data.0.occupied', false)
            ->assertJsonPath('data.0.has_new_order', false);

        // A new order makes it occupied and flags it for the flashing card.
        $order = new Order(['status' => 'NEW', 'items' => [], 'total' => 0, 'currency' => 'EGP', 'table_id' => $table->id]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();

        $this->actingAs($this->admin)->getJson('/api/dashboard/tables/live')
            ->assertOk()
            ->assertJsonPath('data.0.occupied', true)
            ->assertJsonPath('data.0.has_new_order', true);

        // Completing the order drops it from the active set → the card stops
        // flashing, and with no live guest session the table frees up.
        $order->update(['status' => 'COMPLETED']);
        $this->actingAs($this->admin)->getJson('/api/dashboard/tables/live')
            ->assertOk()
            ->assertJsonPath('data.0.occupied', false)
            ->assertJsonPath('data.0.has_new_order', false);
    }

    public function test_bulk_create_stores_each_typed_name_with_a_token(): void
    {
        $this->actingAs($this->admin)->postJson('/api/dashboard/tables/bulk', [
            'dining_area_id' => $this->area->id,
            'labels' => ['Patio 1', 'Patio 2', 'Window', 'Bar'],
        ])->assertCreated()->assertJsonCount(4, 'data');

        $labels = DiningTable::where('dining_area_id', $this->area->id)->pluck('label')->all();
        $this->assertSame(['Patio 1', 'Patio 2', 'Window', 'Bar'], $labels);
        // Every table in the batch is independently QR-ready.
        $this->assertCount(4, DiningTable::whereNotNull('public_token')->whereNotNull('qr_generated_at')->get());
    }

    public function test_bulk_create_trims_and_drops_blank_and_duplicate_names(): void
    {
        $this->actingAs($this->admin)->postJson('/api/dashboard/tables/bulk', [
            'dining_area_id' => $this->area->id,
            'labels' => ['  A  ', '', 'B', 'A', '   '],
        ])->assertCreated()->assertJsonCount(2, 'data');

        $this->assertSame(['A', 'B'], DiningTable::orderBy('id')->pluck('label')->all());
    }

    public function test_bulk_create_rejects_when_every_name_is_blank(): void
    {
        $this->actingAs($this->admin)->postJson('/api/dashboard/tables/bulk', [
            'dining_area_id' => $this->area->id, 'labels' => ['', '   '],
        ])->assertStatus(422)->assertJsonValidationErrors('labels');

        $this->assertSame(0, DiningTable::count());
    }

    public function test_bulk_create_rejects_the_whole_batch_when_a_label_already_exists(): void
    {
        $this->makeTable('Table 2');

        $this->actingAs($this->admin)->postJson('/api/dashboard/tables/bulk', [
            'dining_area_id' => $this->area->id,
            'labels' => ['Table 1', 'Table 2', 'Table 3'],
        ])->assertStatus(422)->assertJsonValidationErrors('labels');

        // No partial insert: only the pre-existing table remains.
        $this->assertSame(1, DiningTable::count());
    }

    private function makeTable(string $label, ?DiningArea $area = null): DiningTable
    {
        $area ??= $this->area;
        $t = new DiningTable([
            'dining_area_id' => $area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $this->restaurant->id;
        $t->branch_id = $area->branch_id;
        $t->save();

        return $t;
    }
}
