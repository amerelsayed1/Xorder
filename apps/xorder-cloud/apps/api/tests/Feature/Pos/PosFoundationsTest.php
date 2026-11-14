<?php

namespace Tests\Feature\Pos;

use App\Enums\Feature;
use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Wave foundations: T0.2, POS-BE-001 (Feature::POS off for everyone until
 * sold), POS-BE-002 (the agreed capability strings and their implies() rules),
 * POS-BE-003 (?resolve=full) and POS-BE-005 (BranchResource additions).
 */
class PosFoundationsTest extends TestCase
{
    use RefreshDatabase;

    // ------------------------------------------------------------- T0.2

    public function test_order_items_has_a_nullable_menu_item_id(): void
    {
        $this->assertTrue(Schema::hasColumn('order_items', 'menu_item_id'));
    }

    // ------------------------------------------------------- POS-BE-001

    public function test_pos_feature_resolves_false_for_every_existing_tenant(): void
    {
        // Not in the default set, not implied by anything: an existing tenant
        // must never wake up entitled to a product it did not buy.
        $this->assertFalse(Feature::defaultSet()['pos']);
        $this->assertFalse(Feature::resolve(['qr_menu' => true, 'system_ordering' => true])['pos']);
    }

    public function test_plans_carry_a_nullable_max_terminals(): void
    {
        $this->assertTrue(Schema::hasColumn('plans', 'max_terminals'));
    }

    // ------------------------------------------------------- POS-BE-002

    public function test_the_agreed_capability_strings_exist_exactly(): void
    {
        $expected = [
            'pos.operate', 'pos.discount', 'pos.price_override', 'pos.void',
            'pos.refund', 'pos.shift_open', 'pos.shift_close',
            'pos.cash_movement', 'pos.reprint', 'pos.provision', 'customers.create',
        ];

        foreach ($expected as $value) {
            $this->assertNotNull(TenantCapability::tryFrom($value), "$value missing");
        }
    }

    public function test_every_pos_verb_implies_pos_operate_which_implies_nothing(): void
    {
        $this->assertSame(TenantCapability::POS_OPERATE, TenantCapability::POS_SHIFT_CLOSE->implies());
        $this->assertSame(TenantCapability::POS_OPERATE, TenantCapability::POS_DISCOUNT->implies());
        $this->assertNull(TenantCapability::POS_OPERATE->implies());
        // customers.create follows the normal rule: its resource HAS a view.
        $this->assertSame(TenantCapability::CUSTOMERS_VIEW, TenantCapability::CUSTOMERS_CREATE->implies());

        $this->assertSame(['pos.operate', 'pos.refund'], TenantCapability::expand(['pos.refund']));
    }

    // ------------------------------------------------------- POS-BE-005

    public function test_branch_resource_serialises_code_and_supported_order_types(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $branch = new Branch(['name_en' => 'Main', 'code' => 'MAIN', 'supported_order_types' => ['dine_in']]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        $bare = new Branch(['name_en' => 'Bare']);
        $bare->restaurant_id = $restaurant->id;
        $bare->save();

        $data = $this->actingAs($owner)->getJson('/api/dashboard/branches')
            ->assertOk()
            ->json('data');

        $main = collect($data)->firstWhere('code', 'MAIN');
        $this->assertSame(['dine_in'], $main['supported_order_types']);

        // [] — never null — so the client iterates without a guard.
        $bareRow = collect($data)->firstWhere('name_en', 'Bare');
        $this->assertSame([], $bareRow['supported_order_types']);
    }

    // ------------------------------------------------------- POS-BE-003

    public function test_resolve_full_includes_auto_applied_option_groups(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $item = MenuItem::factory()->create([
            'restaurant_id' => $restaurant->id,
            'category_id' => Category::factory()->create(['restaurant_id' => $restaurant->id])->id,
        ]);

        // A restaurant-wide "Extras" group with no per-item link at all —
        // exactly what the dashboard endpoint used to hide from the POS.
        $group = new OptionGroup;
        $group->forceFill([
            'restaurant_id' => $restaurant->id,
            'menu_item_id' => null,
            'is_global' => true,
            'apply_scope' => OptionGroup::SCOPE_ALL,
            'name_en' => 'Extras',
            'is_required' => false,
            'is_variant' => false,
            'max_select' => 3,
            'sort_order' => 0,
        ])->save();
        $option = $group->options()->make(['name_en' => 'Cheese', 'price' => 10, 'is_available' => true, 'sort_order' => 0]);
        $option->restaurant_id = $restaurant->id;
        $option->save();

        // Without the flag: the existing payload, no option_groups key.
        $plain = $this->actingAs($owner)->getJson('/api/dashboard/items')->assertOk()->json('data');
        $this->assertArrayNotHasKey('option_groups', $plain[0]);

        // With it: the complete resolved set, auto groups included.
        $full = $this->actingAs($owner)->getJson('/api/dashboard/items?resolve=full')->assertOk()->json('data');
        $groups = collect($full)->firstWhere('id', $item->id)['option_groups'];
        $this->assertSame('Extras', $groups[0]['name_en']);
        $this->assertSame('Cheese', $groups[0]['options'][0]['name_en']);
    }
}
