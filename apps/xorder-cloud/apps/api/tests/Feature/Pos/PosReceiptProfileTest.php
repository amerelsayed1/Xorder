<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\ReceiptProfile;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;

/**
 * A3 / CB-08 — the receipt profile: authored on the platform, delivered in the
 * bootstrap bundle, one row per branch.
 *
 * The assertions that matter: the bundle carries a profile for EVERY active
 * branch (a branch with no row would send the till back to its compiled-in
 * defaults, which is the whole bug), the wire names are the till's own column
 * names so its seeder is a straight mapping, `branch_code` is not
 * `branches.code`, and every write bumps `pos_config_version`.
 */
class PosReceiptProfileTest extends PosTestCase
{
    private const WIRE_KEYS = [
        'branch_id', 'trade_name', 'registration_number', 'activity_code',
        'branch_code', 'country', 'governate', 'region_city', 'street',
        'building_number', 'postal_code', 'floor', 'room', 'landmark',
        'additional_info', 'phone', 'header_note', 'footer_note', 'revision',
    ];

    // --------------------------------------------------------- the bundle

    public function test_the_bundle_carries_a_profile_for_every_active_branch(): void
    {
        $second = new Branch(['name_en' => 'Zamalek', 'code' => 'ZMLK', 'is_active' => true]);
        $second->restaurant_id = $this->restaurant->id;
        $second->save();

        $dormant = new Branch(['name_en' => 'Closed', 'code' => 'CLSD', 'is_active' => false]);
        $dormant->restaurant_id = $this->restaurant->id;
        $dormant->save();

        $claim = $this->claimTerminal();
        $profiles = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($claim['token']))
            ->assertOk()->json('receipt_profiles');

        // Both active branches, neither ever authored; the dormant one is out,
        // exactly like the `branches` block.
        $this->assertCount(2, $profiles);
        $this->assertSame([$this->branch->id, $second->id], array_column($profiles, 'branch_id'));

        // The wire names are the till's pos_receipt_profiles columns, exactly.
        foreach ($profiles as $profile) {
            $this->assertSame(self::WIRE_KEYS, array_keys($profile));
        }
    }

    public function test_an_unauthored_branch_is_projected_from_the_restaurant(): void
    {
        $this->restaurant->forceFill([
            'name_en' => 'Koshary House',
            'tax_registration_number' => '123456789',
        ])->save();
        $this->branch->forceFill(['phone' => '+201000000001'])->save();

        $claim = $this->claimTerminal();
        $profile = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($claim['token']))
            ->assertOk()->json('receipt_profiles.0');

        $this->assertSame('Koshary House', $profile['trade_name']);
        $this->assertSame('123456789', $profile['registration_number']);
        $this->assertSame('+201000000001', $profile['phone']);
        $this->assertSame('EG', $profile['country']); // never blank
        $this->assertSame(0, $profile['revision']);   // nobody has typed it
        // Empty strings, not nulls: the till's columns are NOT NULL DEFAULT ''.
        $this->assertSame('', $profile['governate']);
        $this->assertSame('', $profile['branch_code']);
        $this->assertNull($profile['header_note']);
    }

    public function test_the_authored_profile_reaches_the_till(): void
    {
        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'Koshary House LLC',
            'activity_code' => '5610',
            'branch_code' => '0042',
            'governate' => 'Cairo',
            'region_city' => 'Maadi',
            'street' => 'Road 9',
            'building_number' => '12',
            'header_note' => 'Welcome',
            'footer_note' => 'Wifi: guest',
        ])->assertOk();

        $claim = $this->claimTerminal();
        $profile = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($claim['token']))
            ->assertOk()->json('receipt_profiles.0');

        $this->assertSame('Koshary House LLC', $profile['trade_name']);
        $this->assertSame('5610', $profile['activity_code']);
        // ETA's branch code, NOT the invoice prefix — the branch's own code is
        // still MAADI and the two must never be confused.
        $this->assertSame('0042', $profile['branch_code']);
        $this->assertSame('MAADI', $this->branch->fresh()->code);
        $this->assertSame('Welcome', $profile['header_note']);
        $this->assertSame(1, $profile['revision']);
    }

    // --------------------------------------------------------- authoring

    public function test_saving_bumps_the_config_version_so_tills_re_pull(): void
    {
        $before = (int) $this->restaurant->fresh()->pos_config_version;

        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'Koshary House LLC',
        ])->assertOk();

        $this->assertGreaterThan($before, (int) $this->restaurant->fresh()->pos_config_version);
    }

    public function test_the_index_shows_what_a_till_will_print(): void
    {
        $this->restaurant->forceFill(['tax_registration_number' => '123456789'])->save();

        $body = $this->actingAs($this->owner)->getJson('/api/dashboard/receipt-profiles')
            ->assertOk()->json('data');

        $this->assertSame('123456789', $body['registration_number']);
        $this->assertCount(1, $body['profiles']);
        $this->assertSame(self::WIRE_KEYS, array_keys($body['profiles'][0]));
    }

    public function test_a_stale_revision_is_refused_rather_than_overwriting(): void
    {
        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'First', 'revision' => 0,
        ])->assertOk();

        // The counter's copy still thinks it is at revision 0.
        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'Second', 'revision' => 0,
        ])->assertStatus(409);

        $this->assertSame('First', ReceiptProfile::withoutGlobalScopes()->first()->trade_name);

        // With the right revision it goes through, and the revision moves.
        $body = $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'Second', 'revision' => 1,
        ])->assertOk()->json('data');

        $this->assertSame('Second', $body['trade_name']);
        $this->assertSame(2, $body['revision']);
    }

    public function test_a_four_digit_activity_code_and_a_two_letter_country_are_enforced(): void
    {
        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'activity_code' => '56',
        ])->assertStatus(422)->assertJsonValidationErrors('activity_code');

        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'country' => 'EGY',
        ])->assertStatus(422)->assertJsonValidationErrors('country');

        // A half-typed profile still saves: that is how one is filled in.
        $this->actingAs($this->owner)->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", [
            'trade_name' => 'Koshary House LLC', 'country' => 'eg',
        ])->assertOk()->assertJsonPath('data.country', 'EG');
    }

    // --------------------------------------------------------- gates

    public function test_another_tenants_branch_is_a_404_not_a_403(): void
    {
        $other = Restaurant::factory()->create();
        $foreign = new Branch(['name_en' => 'Foreign', 'code' => 'FRGN']);
        $foreign->restaurant_id = $other->id;
        $foreign->save();

        $this->actingAs($this->owner)
            ->putJson("/api/dashboard/receipt-profiles/{$foreign->id}", ['trade_name' => 'Theirs'])
            ->assertNotFound();

        $this->assertSame(0, ReceiptProfile::withoutGlobalScopes()->count());
    }

    public function test_the_feature_gate_and_the_capability_both_apply(): void
    {
        // No POS feature: the page does not exist for this tenant.
        $this->restaurant->features()->where('feature_key', 'pos')->update(['is_enabled' => false]);
        $this->actingAs($this->owner)->getJson('/api/dashboard/receipt-profiles')->assertForbidden();
        $this->restaurant->features()->where('feature_key', 'pos')->update(['is_enabled' => true]);

        // A member of staff who may see settings but not change them.
        $role = new Role(['name' => 'Viewer']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['settings.view']])->save();
        $viewer = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($viewer)->getJson('/api/dashboard/receipt-profiles')->assertOk();
        $this->actingAs($viewer)
            ->putJson("/api/dashboard/receipt-profiles/{$this->branch->id}", ['trade_name' => 'Nope'])
            ->assertForbidden();
    }

    // --------------------------------------------------------- deviation 6

    public function test_the_tax_registration_number_can_finally_be_authored(): void
    {
        // CLOUD_WAVE1 deviation 6: the column shipped and travelled in the
        // bundle, but UpdateRestaurantProfileRequest silently dropped it.
        $before = (int) $this->restaurant->fresh()->pos_config_version;

        $this->actingAs($this->owner)->putJson('/api/dashboard/restaurant', [
            'tax_registration_number' => '123456789',
        ])->assertOk();

        $this->assertSame('123456789', $this->restaurant->fresh()->tax_registration_number);
        // It rides the bundle, so the tills must be told.
        $this->assertGreaterThan($before, (int) $this->restaurant->fresh()->pos_config_version);

        $claim = $this->claimTerminal();
        $bundle = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($claim['token']))->assertOk()->json();

        $this->assertSame('123456789', $bundle['restaurant']['tax_registration_number']);
        $this->assertSame('123456789', $bundle['receipt_profiles'][0]['registration_number']);
    }
}
