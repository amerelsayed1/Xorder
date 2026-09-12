<?php

namespace Tests\Feature\Pos;

/**
 * CB-09 D8: purchase.manage is held on the dashboard but never travels in the
 * POS bundle. It is the till's own canonical name, so shipping it would light
 * up the till-local Purchasing pane for the people the platform made buyers:
 * two authors of one row. On cloud the platform is the only author.
 */
class PosPurchaseCapabilityWithheldTest extends PosTestCase
{
    public function test_the_owner_bundle_excludes_purchase_manage_while_auth_me_includes_it(): void
    {
        $this->restaurant->features()->create(['feature_key' => 'purchasing', 'is_enabled' => true]);

        ['token' => $token] = $this->claimTerminal();

        $bundle = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk()->json();
        $ownerRow = collect($bundle['staff'])->firstWhere('id', $this->owner->id);

        $this->assertNotContains('purchase.manage', $ownerRow['capabilities']);
        // The filter is surgical: everything else still reaches the till.
        $this->assertContains('pos.operate', $ownerRow['capabilities']);
        $this->assertSame(array_values($ownerRow['capabilities']), $ownerRow['capabilities']);

        $me = $this->actingAs($this->owner)->getJson('/api/auth/me')->assertOk()->json('data.capabilities');
        $this->assertContains('purchase.manage', $me);
    }
}
