<?php

namespace Tests\Feature\Pos;

use App\Enums\LanguageEnum;
use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * Tender-id defect fix (owner go 2026-09-11, POS-BE-013 amendment): a POS
 * restaurant never delivers an empty money.tender_types, so a cloud till
 * always has a platform tender id to pay with. It never needs to fall back to
 * null, which the shift report would count as cash.
 */
class PosDefaultTendersTest extends PosTestCase
{
    private function bundle(string $token): array
    {
        return $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk()->json();
    }

    private function tenderCount(Restaurant $restaurant): int
    {
        return TenderType::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count();
    }

    // ------------------------------------------------------- defaults

    public function test_a_fresh_pos_restaurants_first_bundle_carries_cash_and_card(): void
    {
        $this->assertSame(0, $this->tenderCount($this->restaurant));

        ['token' => $token, 'response' => $claim] = $this->claimTerminal();

        // The bundle inside the claim response and the one from GET agree.
        foreach ([$claim['bootstrap'], $this->bundle($token)] as $bundle) {
            $tenders = collect($bundle['money']['tender_types']);

            $this->assertNotEmpty($tenders);
            $this->assertSame(['cash', 'card'], $tenders->pluck('kind')->all());
            $this->assertTrue($tenders->every(fn ($t) => $t['is_active'] === true && is_int($t['id'])));
        }

        // The factory tenant's default language is Arabic.
        $this->assertSame(['نقدي', 'بطاقة'], collect($claim['bootstrap']['money']['tender_types'])->pluck('name')->all());
    }

    public function test_defaults_are_named_in_the_restaurants_default_language(): void
    {
        $this->restaurant->forceFill(['default_language' => LanguageEnum::EN])->save();

        ['response' => $claim] = $this->claimTerminal();

        $this->assertSame(['Cash', 'Card'], collect($claim['bootstrap']['money']['tender_types'])->pluck('name')->all());
    }

    public function test_the_bundle_says_which_languages_the_menu_is_written_in(): void
    {
        // XORD-005: with default_language it tells the till which name fields to
        // ask for. Bilingual by default.
        ['response' => $claim] = $this->claimTerminal();
        $this->assertTrue($claim['bootstrap']['restaurant']['bilingual']);

        $this->restaurant->forceFill(['bilingual' => false, 'default_language' => LanguageEnum::EN])->save();
        ['response' => $again] = $this->claimTerminal();
        $this->assertFalse($again['bootstrap']['restaurant']['bilingual']);
        $this->assertSame('en', $again['bootstrap']['restaurant']['default_language']);
    }

    public function test_path_b_register_also_delivers_a_non_empty_list(): void
    {
        $role = new Role(['name' => 'Installer']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate', 'pos.provision']])->save();
        $installer = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $body = $this->actingAs($installer)->postJson('/api/pos/terminals/register', [
            'client_transaction_id' => (string) Str::uuid(),
            'name' => 'Back Office Till',
            'branch_id' => $this->branch->id,
        ])->assertCreated()->json();

        $this->assertSame(['cash', 'card'], collect($body['bootstrap']['money']['tender_types'])->pluck('kind')->all());
    }

    public function test_seeding_bumps_the_config_version_like_any_tender_write(): void
    {
        $before = (int) $this->restaurant->fresh()->pos_config_version;

        ['response' => $claim] = $this->claimTerminal();

        // Plain model saves, like the dashboard store path: the PosConfigVersion
        // hook bumps, and the Auditable trait records tender_type.created. The
        // activity-file sink is off under phpunit, so only the bump is asserted.
        $this->assertGreaterThan($before, $claim['bootstrap']['config_version']);
    }

    // ------------------------------------------------------- idempotency

    public function test_a_restaurant_that_already_has_tenders_gets_no_defaults(): void
    {
        $voucher = new TenderType(['name' => 'Voucher', 'kind' => 'other']);
        $voucher->restaurant_id = $this->restaurant->id;
        $voucher->save();

        ['response' => $claim] = $this->claimTerminal();

        $this->assertSame(1, $this->tenderCount($this->restaurant));
        $this->assertSame([$voucher->id], collect($claim['bootstrap']['money']['tender_types'])->pluck('id')->all());
    }

    public function test_an_owner_who_deactivated_every_tender_is_not_overruled(): void
    {
        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash', 'is_active' => false]);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();

        $this->claimTerminal();

        $this->assertSame(1, $this->tenderCount($this->restaurant));
    }

    public function test_a_second_terminal_adds_no_duplicates(): void
    {
        $this->claimTerminal();
        $this->assertSame(2, $this->tenderCount($this->restaurant));

        $this->claimTerminal();
        $this->assertSame(2, $this->tenderCount($this->restaurant));
    }

    // ------------------------------------------------------- isolation

    public function test_seeding_is_per_tenant_and_a_bundle_carries_only_its_own(): void
    {
        [$other, $otherBranch] = $this->otherPosRestaurant();

        // Another tenant already has tenders; ours has none and must still seed.
        $foreign = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $foreign->restaurant_id = $other->id;
        $foreign->save();

        ['response' => $claim] = $this->claimTerminal();

        $ids = collect($claim['bootstrap']['money']['tender_types'])->pluck('id');
        $this->assertCount(2, $ids);
        $this->assertNotContains($foreign->id, $ids);
        $this->assertSame(1, $this->tenderCount($other));
    }

    public function test_the_super_admin_front_door_seeds_the_target_tenant_only(): void
    {
        // The Super Admin carries no tenant, so RestaurantScope is a no-op for
        // them. A scoped "has any tenders?" check would see the other tenant's
        // row and skip seeding.
        [$other] = $this->otherPosRestaurant();
        $foreign = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $foreign->restaurant_id = $other->id;
        $foreign->save();

        $sa = User::factory()->superAdmin()->create();
        $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$this->restaurant->id}/terminals",
                ['name' => 'Till 1', 'branch_id' => $this->branch->id])
            ->assertCreated();

        $this->assertSame(2, $this->tenderCount($this->restaurant));
        $this->assertSame(1, $this->tenderCount($other));
    }

    // ------------------------------------------------------- paying

    public function test_an_order_paid_with_a_delivered_tender_is_accepted(): void
    {
        ['token' => $token, 'response' => $claim] = $this->claimTerminal();
        $card = collect($claim['bootstrap']['money']['tender_types'])->firstWhere('kind', 'card');

        $this->postJson('/api/pos/orders', $this->orderPayload($card['id']), $this->deviceHeaders($token))
            ->assertCreated();

        $this->assertDatabaseHas('order_payments', ['tender_type_id' => $card['id'], 'amount_minor' => 10000]);
    }

    public function test_an_order_paid_with_another_restaurants_tender_is_refused(): void
    {
        [$other] = $this->otherPosRestaurant();
        $foreign = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $foreign->restaurant_id = $other->id;
        $foreign->save();

        ['token' => $token] = $this->claimTerminal();

        $this->postJson('/api/pos/orders', $this->orderPayload($foreign->id), $this->deviceHeaders($token))
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_FAILED');

        $this->assertDatabaseMissing('order_payments', ['tender_type_id' => $foreign->id]);
    }

    // ------------------------------------------------------- fixtures

    /** @return array{0: Restaurant, 1: Branch} */
    private function otherPosRestaurant(): array
    {
        $other = Restaurant::factory()->create(['currency' => 'EGP']);
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        $branch = new Branch(['name_en' => 'Zamalek', 'code' => 'ZAM', 'supported_order_types' => ['takeaway']]);
        $branch->restaurant_id = $other->id;
        $branch->save();

        return [$other, $branch];
    }

    /** @return array<string,mixed> */
    private function orderPayload(int $tenderTypeId): array
    {
        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $item = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00,
            'discounted_price' => null,
        ]);

        return [
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-09-11T08:00:00+02:00',
            'lines' => [
                ['menu_item_id' => $item->id, 'quantity' => 1, 'name_snapshot' => 'Burger'],
            ],
            'payments' => [
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $tenderTypeId, 'amount_minor' => 10000],
            ],
        ];
    }
}
