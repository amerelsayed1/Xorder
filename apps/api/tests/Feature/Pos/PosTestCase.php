<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Shared plumbing for the Cloud Wave 1 POS surface: a pos-entitled tenant,
 * a branch with a code (the invoice prefix), an owner, and a claimed terminal
 * holding a device token — the state every till-facing test starts from.
 */
abstract class PosTestCase extends TestCase
{
    use RefreshDatabase;

    protected Restaurant $restaurant;

    protected Branch $branch;

    protected User $owner;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant = Restaurant::factory()->create(['currency' => 'EGP']);
        $this->restaurant->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        $this->branch = new Branch([
            'name_en' => 'Maadi',
            'code' => 'MAADI',
            'supported_order_types' => ['dine_in', 'takeaway', 'delivery'],
        ]);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();

        $this->owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    /** Provision (dashboard) + claim (till): the Path A happy path, reused everywhere. */
    protected function claimTerminal(array $claimOverrides = []): array
    {
        $provision = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 1', 'branch_id' => $this->branch->id])
            ->assertCreated()
            ->json('data');

        $code = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")
            ->assertOk()
            ->json('pairing_code');

        // The claim itself is unauthenticated — a fresh machine has no login.
        // actingAs() above pinned the owner to the guard for the rest of the
        // test; drop that, or every device request after this one would carry
        // a dashboard user a real till never has (and be audited as them).
        $this->app['auth']->forgetGuards();
        $response = $this->postJson('/api/pos/terminals/claim', array_merge([
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => $code,
            'platform' => 'windows',
            'app_version' => '1.4.2',
            'fingerprint' => 'sha256:test-device',
        ], $claimOverrides))->assertOk()->json();

        return [
            'token' => $response['device_token'],
            'terminal' => PosTerminal::withoutGlobalScopes()->where('terminal_id', $response['terminal']['id'])->first(),
            'response' => $response,
            'pairing_code' => $code,
        ];
    }

    /** @return array<string,string> */
    protected function deviceHeaders(string $token): array
    {
        return ['Authorization' => 'Bearer '.$token];
    }
}
