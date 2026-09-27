<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Enums\SubscriptionStatus;
use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\Unit;
use App\Models\User;
use App\Services\UnitCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * CB-09 slice a: the purchasing feature, the purchase.manage capability,
 * units and suppliers.
 *
 * The default tenant here has `purchasing` and deliberately NOT `pos`: the
 * owner ruled purchasing standalone (2026-09-12), so everything must work for
 * a café or cloud kitchen with no till.
 */
class PurchasingFoundationsTest extends TestCase
{
    use RefreshDatabase;

    private string $activityDir;

    // The audit trail is file-based (the daily activity files are the system
    // of record; there is no audit table to assert on). Point it at a scratch
    // directory, as AuditLogTest does.
    protected function setUp(): void
    {
        parent::setUp();

        $this->activityDir = storage_path('framework/testing/audit-'.uniqid());
        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $this->activityDir.'/activity.log',
        ]);
        Log::forgetChannel('activity');
    }

    protected function tearDown(): void
    {
        Log::forgetChannel('activity');
        File::deleteDirectory($this->activityDir);

        parent::tearDown();
    }

    /** @return list<array<string,mixed>> every event recorded today */
    private function events(): array
    {
        $file = $this->activityDir.'/activity-'.now()->format('Y-m-d').'.log';

        return file_exists($file)
            ? array_map(fn ($l) => json_decode($l, true), array_values(array_filter(explode("\n", file_get_contents($file)))))
            : [];
    }

    private function event(string $action, int $restaurantId): ?array
    {
        return collect($this->events())->first(
            // The activity file names the tenant `tenant_id`.
            fn (array $e) => ($e['action'] ?? null) === $action && ($e['tenant_id'] ?? null) === $restaurantId,
        );
    }

    private function tenant(array $features = ['purchasing'], array $attributes = []): Restaurant
    {
        $restaurant = Restaurant::factory()->create($attributes);
        foreach ($features as $key) {
            $restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }

        return $restaurant;
    }

    private function owner(Restaurant $restaurant): User
    {
        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    private function staffWith(Restaurant $restaurant, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($restaurant->id, $role->id)->create();
    }

    private function supplier(Restaurant $restaurant, array $attributes = []): Supplier
    {
        $supplier = new Supplier(array_merge(['name_en' => 'Cairo Poultry'], $attributes));
        $supplier->restaurant_id = $restaurant->id;
        $supplier->save();

        return $supplier;
    }

    /**
     * One row in whichever table names a supplier, written straight to the
     * table: the delete check only asks whether such a row exists, and going
     * through the real endpoints would drag a whole order-to-payment flow into
     * a test about deleting a supplier.
     */
    private function attachPurchasingDocument(string $kind, Restaurant $restaurant, Supplier $supplier): void
    {
        $branch = new Branch(['name_en' => 'Downtown']);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        $common = [
            'restaurant_id' => $restaurant->id,
            'branch_id' => $branch->id,
            'supplier_id' => $supplier->id,
            'supplier_name' => $supplier->name_en,
            'currency' => 'EGP',
            'created_at' => now(),
            'updated_at' => now(),
        ];

        match ($kind) {
            'order' => DB::table('purchase_orders')->insert($common + ['status' => 'draft']),
            'invoice' => DB::table('supplier_invoices')->insert($common + [
                'number' => 'INV-1', 'total_minor' => 5000,
                'issued_at' => '2026-09-01', 'due_at' => '2026-09-01',
            ]),
            'payment' => DB::table('supplier_payments')->insert($common + [
                'method' => 'cash', 'amount_minor' => 5000, 'paid_at' => '2026-09-01',
            ]),
        };
    }

    private function unit(Restaurant $restaurant, array $attributes = []): Unit
    {
        $unit = new Unit(array_merge(['code' => 'tray30', 'name_en' => 'Tray of 30'], $attributes));
        $unit->restaurant_id = $restaurant->id;
        $unit->save();

        return $unit;
    }

    // ---------------------------------------------------------- foundations

    public function test_the_tables_exist_and_carry_no_balance_column(): void
    {
        $this->assertTrue(Schema::hasTable('units'));
        $this->assertTrue(Schema::hasTable('suppliers'));
        $this->assertFalse(Schema::hasColumn('suppliers', 'balance'));
        $this->assertFalse(Schema::hasColumn('suppliers', 'balance_minor'));
    }

    public function test_purchasing_resolves_false_for_every_existing_tenant(): void
    {
        $this->assertFalse(Feature::defaultSet()['purchasing']);
        $this->assertFalse(Feature::resolve(['qr_menu' => true, 'pos' => true])['purchasing']);
        $this->assertFalse(Restaurant::factory()->create()->hasFeature('purchasing'));
    }

    public function test_purchasing_is_standalone_and_does_not_pull_in_pos(): void
    {
        $this->assertSame([], Feature::PURCHASING->requires());

        $resolved = Feature::resolve(['purchasing' => true]);
        $this->assertTrue($resolved['purchasing']);
        $this->assertFalse($resolved['pos']);
    }

    public function test_purchase_manage_is_a_live_single_verb(): void
    {
        $cap = TenantCapability::PURCHASE_MANAGE;

        $this->assertSame('purchase.manage', $cap->value);
        $this->assertSame('purchase', $cap->resource());
        $this->assertSame('manage', $cap->action());
        $this->assertSame('buying', $cap->group());
        $this->assertNull($cap->implies());
        // Not a pre-split value: it passes through expand() untouched.
        $this->assertArrayNotHasKey('purchase.manage', TenantCapability::legacyManageMap());
        $this->assertSame(['purchase.manage'], TenantCapability::expand(['purchase.manage']));
    }

    public function test_purchase_manage_has_a_label_in_both_languages(): void
    {
        foreach (['en', 'ar'] as $locale) {
            $label = __('xorder.capabilities.purchase_manage', [], $locale);
            $this->assertNotSame('xorder.capabilities.purchase_manage', $label, $locale);
        }
    }

    // ----------------------------------------------------------- gate stack

    public function test_feature_off_blocks_even_the_owner(): void
    {
        // A pos tenant without purchasing: pos does not grant it either.
        $restaurant = $this->tenant(['pos']);
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->getJson('/api/dashboard/suppliers')->assertForbidden();
        $this->actingAs($owner)->getJson('/api/dashboard/units')->assertForbidden();
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X'])->assertForbidden();
        $this->assertSame(0, Supplier::withoutGlobalScopes()->count());
    }

    public function test_staff_without_the_capability_is_refused_reads_and_writes(): void
    {
        $restaurant = $this->tenant();
        $clerk = $this->staffWith($restaurant, ['menu.view', 'settings.view', 'settings.update']);

        $this->actingAs($clerk)->getJson('/api/dashboard/suppliers')->assertForbidden();
        $this->actingAs($clerk)->getJson('/api/dashboard/units')->assertForbidden();
        $this->actingAs($clerk)->postJson('/api/dashboard/suppliers', ['name_en' => 'X'])->assertForbidden();
        $this->actingAs($clerk)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_en' => 'Crate'])->assertForbidden();
    }

    public function test_staff_holding_purchase_manage_can_read_and_write(): void
    {
        $restaurant = $this->tenant();
        $buyer = $this->staffWith($restaurant, ['purchase.manage']);

        $this->actingAs($buyer)->getJson('/api/dashboard/suppliers')->assertOk();
        $this->actingAs($buyer)->postJson('/api/dashboard/suppliers', ['name_en' => 'Nile Dairy', 'phone' => '0100000000'])->assertCreated();
        $this->actingAs($buyer)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_en' => 'Crate'])->assertCreated();
    }

    public function test_a_tenant_with_purchasing_but_no_pos_can_use_it(): void
    {
        $restaurant = $this->tenant(['purchasing']);
        $owner = $this->owner($restaurant);
        $this->assertFalse($restaurant->hasFeature('pos'));

        $this->actingAs($owner)->getJson('/api/dashboard/units')->assertOk()->assertJsonCount(7, 'data');
        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Cairo Poultry', 'phone' => '0100000000'])
            ->assertCreated()->json('data.id');
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$id}", ['name_en' => 'Cairo Poultry Co.', 'phone' => '0100000000'])
            ->assertOk()->assertJsonPath('data.name_en', 'Cairo Poultry Co.');
    }

    public function test_a_lapsed_subscription_blocks_writes_but_not_reads(): void
    {
        $restaurant = $this->tenant(['purchasing'], ['subscription_status' => SubscriptionStatus::EXPIRED]);
        $owner = $this->owner($restaurant);
        $supplier = $this->supplier($restaurant);

        $this->actingAs($owner)->getJson('/api/dashboard/suppliers')->assertOk();
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X'])
            ->assertForbidden()->assertJsonPath('code', 'subscription_inactive');
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$supplier->id}", ['name_en' => 'Y'])
            ->assertForbidden()->assertJsonPath('code', 'subscription_inactive');
    }

    // ------------------------------------------------------ tenant isolation

    public function test_another_tenants_supplier_and_unit_are_404(): void
    {
        $mine = $this->tenant();
        $theirs = $this->tenant();
        $owner = $this->owner($mine);
        $supplier = $this->supplier($theirs);
        $unit = $this->unit($theirs);

        $this->actingAs($owner)->getJson("/api/dashboard/suppliers/{$supplier->id}")->assertNotFound();
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$supplier->id}", ['name_en' => 'Hijacked'])->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/units/{$unit->id}")->assertNotFound();
        $this->actingAs($owner)->putJson("/api/dashboard/units/{$unit->id}", ['name_en' => 'Hijacked'])->assertNotFound();

        $this->assertSame('Cairo Poultry', $supplier->fresh()->name_en);
        $this->assertSame('Tray of 30', $unit->fresh()->name_en);

        // And the lists only ever show your own rows.
        $this->actingAs($owner)->getJson('/api/dashboard/suppliers')->assertOk()->assertJsonCount(0, 'data');
        $codes = collect($this->actingAs($owner)->getJson('/api/dashboard/units')->json('data'))->pluck('code');
        $this->assertNotContains('tray30', $codes);
    }

    public function test_restaurant_id_in_the_body_is_ignored(): void
    {
        $mine = $this->tenant();
        $theirs = $this->tenant();
        $owner = $this->owner($mine);

        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', [
            'name_en' => 'Mine', 'phone' => '0100000000', 'restaurant_id' => $theirs->id,
        ])->assertCreated()->json('data.id');

        $this->assertSame($mine->id, Supplier::withoutGlobalScopes()->find($id)->restaurant_id);
    }

    // ---------------------------------------------------------------- units

    public function test_default_units_are_seeded_once_and_idempotently(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $codes = collect($this->actingAs($owner)->getJson('/api/dashboard/units')->assertOk()->json('data'))->pluck('code')->all();
        $this->assertSame(['ea', 'kg', 'g', 'l', 'ml', 'box', 'pack'], $codes);

        $kg = Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->where('code', 'kg')->first();
        $this->assertSame('كيلوجرام', $kg->name_ar);
        $this->assertSame('KGM', $kg->eta_unit_type);
        $this->assertTrue($kg->allows_fraction);

        // A retired default stays retired: seeding never re-creates or revives.
        $kg->forceFill(['is_active' => false])->save();
        $this->actingAs($owner)->getJson('/api/dashboard/units')->assertOk()->assertJsonCount(7, 'data');
        app(UnitCatalog::class)->ensureDefaults($restaurant->id);
        $this->assertSame(7, Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
        $this->assertFalse($kg->fresh()->is_active);

        // Seeding writes no audit events in the reader's name.
        $this->assertNull($this->event('unit.created', $restaurant->id));
    }

    public function test_a_hand_made_unit_that_takes_a_default_code_first_is_kept(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'box', 'name_en' => 'Carton'])->assertCreated();
        $this->actingAs($owner)->getJson('/api/dashboard/units')->assertOk()->assertJsonCount(7, 'data');

        $this->assertSame('Carton', Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->where('code', 'box')->value('name_en'));
    }

    public function test_a_unit_code_is_immutable(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);
        $unit = $this->unit($restaurant);

        $this->actingAs($owner)->putJson("/api/dashboard/units/{$unit->id}", [
            'code' => 'renamed', 'name_en' => 'Tray (30 eggs)', 'allows_fraction' => false, 'is_active' => true,
        ])->assertOk()->assertJsonPath('data.code', 'tray30')->assertJsonPath('data.name_en', 'Tray (30 eggs)');

        $this->assertSame('tray30', $unit->fresh()->code);
    }

    public function test_unit_code_shape_and_uniqueness(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        foreach (['1kg', 'with space', 'bad-dash', 'toolongcode_seventeen', ''] as $bad) {
            $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => $bad, 'name_en' => 'X'])
                ->assertUnprocessable()->assertJsonValidationErrors('code');
        }

        // Upper case is folded, not refused.
        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'Sack', 'name_en' => 'Sack'])
            ->assertCreated()->assertJsonPath('data.code', 'sack')->assertJsonPath('data.eta_unit_type', 'EA');

        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'sack', 'name_en' => 'Sack again'])
            ->assertUnprocessable()->assertJsonValidationErrors('code');

        // The same code in another tenant is fine.
        $other = $this->tenant();
        $this->actingAs($this->owner($other))->postJson('/api/dashboard/units', ['code' => 'sack', 'name_en' => 'Sack'])
            ->assertCreated();
    }

    public function test_unit_needs_a_name_and_a_shaped_eta_type(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'crate'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');
        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_ar' => 'صندوق', 'eta_unit_type' => 'toolong7'])
            ->assertUnprocessable()->assertJsonValidationErrors('eta_unit_type');
        // Arabic-only is a valid name.
        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_ar' => 'صندوق', 'eta_unit_type' => 'cr'])
            ->assertCreated()->assertJsonPath('data.eta_unit_type', 'CR');
    }

    public function test_there_is_no_delete_route_for_units(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);
        $unit = $this->unit($restaurant);

        $this->actingAs($owner)->deleteJson("/api/dashboard/units/{$unit->id}")->assertStatus(405);
        $this->assertNotNull($unit->fresh());
    }

    public function test_an_unused_supplier_can_be_deleted_and_it_is_audited(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);
        $supplier = $this->supplier($restaurant);

        $this->actingAs($owner)->deleteJson("/api/dashboard/suppliers/{$supplier->id}")->assertOk();
        $this->assertNull(Supplier::withoutGlobalScopes()->find($supplier->id));
        $this->assertSame($owner->id, $this->event('supplier.deleted', $restaurant->id)['actor_id'] ?? null);
    }

    public function test_a_supplier_named_by_any_purchasing_document_is_kept(): void
    {
        // Each of the three tables that point at a supplier, one at a time: the
        // row is part of what that document means, so the answer is retire.
        foreach (['order', 'invoice', 'payment'] as $kind) {
            $restaurant = $this->tenant();
            $owner = $this->owner($restaurant);
            $supplier = $this->supplier($restaurant);
            $this->attachPurchasingDocument($kind, $restaurant, $supplier);

            $this->actingAs($owner)->deleteJson("/api/dashboard/suppliers/{$supplier->id}")
                ->assertStatus(409)
                ->assertJsonPath('message', __('xorder.messages.supplier_has_purchasing'));
            $this->assertNotNull($supplier->fresh(), "deleted despite a {$kind}");
        }
    }

    public function test_another_tenants_supplier_cannot_be_deleted(): void
    {
        $mine = $this->tenant();
        $theirs = $this->tenant();
        $supplier = $this->supplier($theirs);

        $this->actingAs($this->owner($mine))->deleteJson("/api/dashboard/suppliers/{$supplier->id}")
            ->assertNotFound();
        $this->assertNotNull($supplier->fresh());
    }

    public function test_deleting_a_supplier_needs_the_capability_and_a_live_subscription(): void
    {
        $restaurant = $this->tenant();
        $clerk = $this->staffWith($restaurant, ['menu.view']);
        $supplier = $this->supplier($restaurant);

        $this->actingAs($clerk)->deleteJson("/api/dashboard/suppliers/{$supplier->id}")->assertForbidden();

        $lapsed = $this->tenant(['purchasing'], ['subscription_status' => SubscriptionStatus::EXPIRED]);
        $theirs = $this->supplier($lapsed);
        $this->actingAs($this->owner($lapsed))->deleteJson("/api/dashboard/suppliers/{$theirs->id}")
            ->assertForbidden()->assertJsonPath('code', 'subscription_inactive');

        $this->assertNotNull($supplier->fresh());
        $this->assertNotNull($theirs->fresh());
    }

    // ------------------------------------------------------------ suppliers

    public function test_supplier_phone_is_required_but_its_shape_is_not_policed(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        foreach ([[], ['phone' => null], ['phone' => '']] as $missing) {
            $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X'] + $missing)
                ->assertUnprocessable()->assertJsonValidationErrors('phone');
        }

        // A supplier is reached however the supplier is reached: a landline
        // with an extension, or an Arabic-typed mobile, both stored verbatim.
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'phone' => '02 2735 1234 ext 4'])
            ->assertCreated()->assertJsonPath('data.phone', '02 2735 1234 ext 4');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Y', 'phone' => '٠١٠٢٢٢٢٣٣٣٣'])
            ->assertCreated()->assertJsonPath('data.phone', '٠١٠٢٢٢٢٣٣٣٣');

        // Editing an existing supplier cannot silently drop its phone either.
        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Z', 'phone' => '0100000000'])
            ->assertCreated()->json('data.id');
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$id}", ['name_en' => 'Z'])
            ->assertUnprocessable()->assertJsonValidationErrors('phone');
    }

    public function test_supplier_code_is_unique_when_set_and_many_can_have_none(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'A', 'phone' => '0100000000'])->assertCreated();
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'B', 'phone' => '0100000000', 'code' => ''])
            ->assertCreated()->assertJsonPath('data.code', null);
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'C', 'phone' => '0100000000', 'code' => null])->assertCreated();

        $d = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'D', 'phone' => '0100000000', 'code' => 'SUP-01'])
            ->assertCreated()->json('data.id');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'E', 'phone' => '0100000000', 'code' => 'SUP-01'])
            ->assertUnprocessable()->assertJsonValidationErrors('code');

        // Re-saving D with its own code is not a clash.
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$d}", ['name_en' => 'D2', 'phone' => '0100000000', 'code' => 'SUP-01'])->assertOk();

        // Another tenant may use the same code.
        $this->actingAs($this->owner($this->tenant()))
            ->postJson('/api/dashboard/suppliers', ['name_en' => 'Z', 'phone' => '0100000000', 'code' => 'SUP-01'])->assertCreated();

        $this->assertSame(4, Supplier::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
    }

    public function test_supplier_needs_a_name_and_non_negative_terms(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['contact_name' => 'Hassan', 'phone' => '0100000000'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'phone' => '0100000000', 'payment_term_days' => -1])
            ->assertUnprocessable()->assertJsonValidationErrors('payment_term_days');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'phone' => '0100000000', 'email' => 'not-an-email'])
            ->assertUnprocessable()->assertJsonValidationErrors('email');

        // Either language alone is a name; terms are still settable by API for
        // the invoice form's due-date default, they just left the editor.
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_ar' => 'مورد', 'phone' => '0100000000', 'payment_term_days' => 30])
            ->assertCreated()->assertJsonPath('data.payment_term_days', 30)->assertJsonPath('data.is_active', true);
    }

    public function test_retiring_a_supplier_is_an_update_and_it_is_audited(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Cairo Poultry', 'phone' => '0100000000'])
            ->assertCreated()->json('data.id');
        $this->assertSame($owner->id, $this->event('supplier.created', $restaurant->id)['actor_id'] ?? null);

        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$id}", ['name_en' => 'Cairo Poultry', 'phone' => '0100000000', 'is_active' => false])
            ->assertOk()->assertJsonPath('data.is_active', false);
        $updated = $this->event('supplier.updated', $restaurant->id);
        $this->assertSame($owner->id, $updated['actor_id'] ?? null);
        $this->assertSame(['old' => true, 'new' => false], $updated['properties']['changes']['is_active'] ?? null);
        $this->assertSame($owner->id, Supplier::withoutGlobalScopes()->find($id)->updated_by);
    }

    public function test_creating_a_unit_is_audited(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_en' => 'Crate'])->assertCreated();

        $this->assertSame($owner->id, $this->event('unit.created', $restaurant->id)['actor_id'] ?? null);
    }
}
