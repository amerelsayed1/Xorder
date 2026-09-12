<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Enums\SubscriptionStatus;
use App\Enums\TenantCapability;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\Unit;
use App\Models\User;
use App\Services\UnitCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
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
        $this->actingAs($buyer)->postJson('/api/dashboard/suppliers', ['name_en' => 'Nile Dairy'])->assertCreated();
        $this->actingAs($buyer)->postJson('/api/dashboard/units', ['code' => 'crate', 'name_en' => 'Crate'])->assertCreated();
    }

    public function test_a_tenant_with_purchasing_but_no_pos_can_use_it(): void
    {
        $restaurant = $this->tenant(['purchasing']);
        $owner = $this->owner($restaurant);
        $this->assertFalse($restaurant->hasFeature('pos'));

        $this->actingAs($owner)->getJson('/api/dashboard/units')->assertOk()->assertJsonCount(7, 'data');
        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Cairo Poultry'])
            ->assertCreated()->json('data.id');
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$id}", ['name_en' => 'Cairo Poultry Co.'])
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
            'name_en' => 'Mine', 'restaurant_id' => $theirs->id,
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

    public function test_there_is_no_delete_route_for_units_or_suppliers(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);
        $unit = $this->unit($restaurant);
        $supplier = $this->supplier($restaurant);

        $this->actingAs($owner)->deleteJson("/api/dashboard/units/{$unit->id}")->assertStatus(405);
        $this->actingAs($owner)->deleteJson("/api/dashboard/suppliers/{$supplier->id}")->assertStatus(405);
        $this->assertNotNull($unit->fresh());
        $this->assertNotNull($supplier->fresh());
    }

    // ------------------------------------------------------------ suppliers

    public function test_supplier_tax_number_is_exactly_nine_digits(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        foreach (['12345678', '1234567890', '12345678a', '123-456-789'] as $bad) {
            $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'tax_number' => $bad])
                ->assertUnprocessable()->assertJsonValidationErrors('tax_number');
        }

        // Arabic-Indic digits are folded to Latin before the check.
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'tax_number' => '٢٠٤١٢٣٤٥٦'])
            ->assertCreated()->assertJsonPath('data.tax_number', '204123456');

        // Blank means none.
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Y', 'tax_number' => ''])
            ->assertCreated()->assertJsonPath('data.tax_number', null);
    }

    public function test_supplier_code_is_unique_when_set_and_many_can_have_none(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'A'])->assertCreated();
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'B', 'code' => ''])
            ->assertCreated()->assertJsonPath('data.code', null);
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'C', 'code' => null])->assertCreated();

        $d = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'D', 'code' => 'SUP-01'])
            ->assertCreated()->json('data.id');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'E', 'code' => 'SUP-01'])
            ->assertUnprocessable()->assertJsonValidationErrors('code');

        // Re-saving D with its own code is not a clash.
        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$d}", ['name_en' => 'D2', 'code' => 'SUP-01'])->assertOk();

        // Another tenant may use the same code.
        $this->actingAs($this->owner($this->tenant()))
            ->postJson('/api/dashboard/suppliers', ['name_en' => 'Z', 'code' => 'SUP-01'])->assertCreated();

        $this->assertSame(4, Supplier::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
    }

    public function test_supplier_needs_a_name_and_non_negative_terms(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['contact_name' => 'Hassan'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'payment_term_days' => -1])
            ->assertUnprocessable()->assertJsonValidationErrors('payment_term_days');
        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'X', 'email' => 'not-an-email'])
            ->assertUnprocessable()->assertJsonValidationErrors('email');

        $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_ar' => 'مورد', 'payment_term_days' => 30])
            ->assertCreated()->assertJsonPath('data.payment_term_days', 30)->assertJsonPath('data.is_active', true);
    }

    public function test_retiring_a_supplier_is_an_update_and_it_is_audited(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);

        $id = $this->actingAs($owner)->postJson('/api/dashboard/suppliers', ['name_en' => 'Cairo Poultry'])
            ->assertCreated()->json('data.id');
        $this->assertSame($owner->id, $this->event('supplier.created', $restaurant->id)['actor_id'] ?? null);

        $this->actingAs($owner)->putJson("/api/dashboard/suppliers/{$id}", ['name_en' => 'Cairo Poultry', 'is_active' => false])
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
