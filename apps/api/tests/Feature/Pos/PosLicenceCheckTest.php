<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\PosLicence;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\LicenceIssuer;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Illuminate\Testing\TestResponse;

/**
 * R2, POS-BE-031 — the online licence verdict and the dashboard status that
 * drives it.
 *
 * What the till depends on: one `status` from a fixed set, the operator's
 * status winning over the dates, "no live licence" as a 404 rather than a
 * verdict, and `enforcement` reaching it on bootstrap and activation so it
 * knows whether to ask at all.
 */
class PosLicenceCheckTest extends PosTestCase
{
    private User $superAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $pair = sodium_crypto_sign_keypair();
        config([
            'licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair)),
            'licence.key_id' => 'v1',
        ]);

        $this->superAdmin = User::factory()->superAdmin()->create();
    }

    /** @param  array<string,mixed>  $overrides */
    private function issue(array $overrides = []): PosLicence
    {
        return app(LicenceIssuer::class)->issue($this->restaurant, $overrides + [
            'issued_at' => now()->subDay(),
            'expires_at' => now()->addYear(),
            'max_terminals' => 2,
            'modes' => ['cloud'],
        ])['licence'];
    }

    private function check(string $token, array $body = []): TestResponse
    {
        return $this->postJson('/api/pos/license/check', $body, $this->deviceHeaders($token));
    }

    public function test_a_live_licence_answers_valid_with_the_agreed_fields(): void
    {
        $licence = $this->issue();
        ['token' => $token] = $this->claimTerminal();

        $this->check($token)
            ->assertOk()
            ->assertJsonPath('status', 'valid')
            ->assertJsonPath('licence_ref', $licence->licence_ref)
            ->assertJsonPath('lifetime', false)
            ->assertJsonPath('enforcement', 'online')
            ->assertJsonPath('message', null)
            ->assertJsonPath('grace_policy.cache_seconds', 259200)
            ->assertJsonStructure([
                'status', 'licence_ref', 'starts_at', 'expires_at', 'lifetime', 'grace_days',
                'warn_days', 'max_terminals', 'max_users', 'features', 'enforcement',
                'message', 'server_time', 'grace_policy' => ['cache_seconds'],
            ]);
    }

    public function test_the_dates_decide_when_the_operator_has_not(): void
    {
        ['token' => $token] = $this->claimTerminal();
        $licence = $this->issue(['expires_at' => now()->addDays(10)]);

        $this->check($token)->assertJsonPath('status', 'expiring_soon');

        Carbon::setTestNow(now()->addDays(12));
        $this->check($token)->assertJsonPath('status', 'in_grace');

        Carbon::setTestNow(now()->addDays($licence->grace_days + 1));
        $this->check($token)->assertJsonPath('status', 'expired')
            ->assertJsonPath('message', __('xorder.errors.licence_expired'));
        Carbon::setTestNow();
    }

    public function test_a_licence_that_has_not_started_is_not_yet_valid(): void
    {
        ['token' => $token] = $this->claimTerminal();
        $licence = $this->issue(['issued_at' => now()->addWeek()]);

        $this->check($token)
            ->assertJsonPath('status', 'not_yet_valid')
            ->assertJsonPath('starts_at', $licence->issued_at->toIso8601String());
    }

    public function test_suspension_wins_over_the_dates_and_resume_restores_them(): void
    {
        $licence = $this->issue();
        ['token' => $token] = $this->claimTerminal();

        $this->actingAs($this->superAdmin)
            ->postJson("/api/admin/pos/licences/{$licence->id}/suspend", ['reason' => 'Invoice unpaid'])
            ->assertOk()
            ->assertJsonPath('data.status', 'suspended')
            ->assertJsonPath('data.verdict', 'suspended')
            ->assertJsonPath('data.suspended_reason', 'Invoice unpaid');

        $this->check($token)
            ->assertJsonPath('status', 'suspended')
            ->assertJsonPath('message', 'Invoice unpaid');

        $this->actingAs($this->superAdmin)
            ->postJson("/api/admin/pos/licences/{$licence->id}/resume")
            ->assertOk()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.suspended_at', null);

        $this->check($token)->assertJsonPath('status', 'valid');
    }

    public function test_a_forced_expiry_is_expired_while_the_row_stays_live(): void
    {
        $licence = $this->issue();
        ['token' => $token] = $this->claimTerminal();

        $this->actingAs($this->superAdmin)
            ->postJson("/api/admin/pos/licences/{$licence->id}/expire")
            ->assertOk()
            ->assertJsonPath('data.status', 'expired')
            // Not revoked: the till hears "expired", not "no licence".
            ->assertJsonPath('data.revoked_at', null);

        $this->check($token)->assertOk()->assertJsonPath('status', 'expired');
    }

    public function test_each_status_change_is_audited(): void
    {
        // The trail is the per-day activity file (see ActivityLogFileTest).
        $dir = storage_path('framework/testing/activity-'.uniqid());
        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $dir.'/activity.log',
        ]);
        Log::forgetChannel('activity');

        $licence = $this->issue();

        foreach (['suspend', 'resume', 'expire'] as $action) {
            $this->actingAs($this->superAdmin)
                ->postJson("/api/admin/pos/licences/{$licence->id}/{$action}")
                ->assertOk();
        }

        $actions = collect(explode("\n", trim(file_get_contents($dir.'/activity-'.now()->format('Y-m-d').'.log'))))
            ->map(fn ($line) => json_decode($line, true)['action'] ?? null);

        Log::forgetChannel('activity');
        File::deleteDirectory($dir);

        foreach (['pos_licence.suspended', 'pos_licence.resumed', 'pos_licence.expired'] as $event) {
            $this->assertContains($event, $actions, $event);
        }
    }

    public function test_a_revoked_or_superseded_licence_is_not_found_and_cannot_change_status(): void
    {
        $licence = $this->issue();
        ['token' => $token] = $this->claimTerminal();

        app(LicenceIssuer::class)->revoke($licence, 'test');

        $this->check($token)->assertNotFound()->assertJsonPath('code', 'licence_not_found');

        $this->actingAs($this->superAdmin)
            ->postJson("/api/admin/pos/licences/{$licence->id}/suspend")
            ->assertStatus(422)
            ->assertJsonPath('code', 'LICENCE_NOT_LIVE');
    }

    public function test_a_renewal_is_what_the_till_is_checked_against(): void
    {
        $original = $this->issue();
        ['token' => $token] = $this->claimTerminal();

        $renewal = app(LicenceIssuer::class)->renew($original, [
            'issued_at' => now()->subDay(),
            'expires_at' => now()->addYears(2),
        ])['licence'];

        $this->assertSame('online', $renewal->enforcement);
        $this->check($token)->assertJsonPath('licence_ref', $renewal->licence_ref);
    }

    public function test_no_licence_is_a_404_with_the_agreed_code(): void
    {
        ['token' => $token] = $this->claimTerminal();

        $this->check($token)->assertNotFound()->assertJsonPath('code', 'licence_not_found');
    }

    public function test_the_check_needs_the_device_credential(): void
    {
        $this->issue();

        $this->postJson('/api/pos/license/check', [], ['Authorization' => 'Bearer xdt_nonsense'])
            ->assertUnauthorized()
            ->assertJsonPath('code', 'DEVICE_TOKEN_INVALID');
    }

    public function test_a_lapsed_pos_feature_still_hears_its_verdict(): void
    {
        $this->issue();
        ['token' => $token] = $this->claimTerminal();
        $this->restaurant->features()->where('feature_key', 'pos')->update(['is_enabled' => false]);

        $this->check($token)->assertOk()->assertJsonPath('status', 'valid');
    }

    public function test_the_check_records_telemetry_on_the_terminal(): void
    {
        $licence = $this->issue();
        ['token' => $token, 'terminal' => $terminal] = $this->claimTerminal();

        $this->check($token, ['app_version' => '1.5.0', 'licence_expires_at' => '2027-01-01T00:00:00+00:00'])->assertOk();

        $terminal = PosTerminal::withoutGlobalScopes()->find($terminal->id);
        $this->assertNotNull($terminal->last_licence_check_at);
        $this->assertSame($licence->id, $terminal->licence_id);
        $this->assertSame('1.5.0', $terminal->app_version);
        $this->assertSame('2027-01-01', $terminal->reported_licence_expires_at->toDateString());
    }

    public function test_a_throttled_check_carries_the_agreed_code(): void
    {
        $this->issue();
        ['token' => $token] = $this->claimTerminal();

        // 60 a minute, a budget the till shares with its other device calls.
        $response = null;
        for ($i = 0; $i < 61; $i++) {
            $response = $this->check($token);
            if ($response->status() === 429) {
                break;
            }
        }

        $response->assertStatus(429)->assertJsonPath('code', 'TOO_MANY_ATTEMPTS');
    }

    public function test_bootstrap_and_activation_carry_enforcement(): void
    {
        $issued = app(LicenceIssuer::class)->issue($this->restaurant, [
            'issued_at' => now()->subDay(), 'expires_at' => now()->addYear(), 'modes' => ['cloud'],
        ]);
        ['token' => $token] = $this->claimTerminal();

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))
            ->assertOk()
            ->assertJsonPath('licence.enforcement', 'online')
            ->assertJsonPath('licence.signature', $issued['licence']->signature);

        $this->postJson('/api/pos/licence/activate', ['key' => $issued['key']])
            ->assertOk()
            ->assertJsonPath('enforcement', 'online')
            ->assertJsonPath('payload', $issued['licence']->payload);
    }

    public function test_an_offline_licence_is_enforced_by_its_file(): void
    {
        $issued = app(LicenceIssuer::class)->issue(null, [
            'customer_name' => 'Island Grill', 'customer_slug' => 'island-grill',
            'issued_at' => now()->subDay(), 'expires_at' => now()->addYear(), 'modes' => ['offline'],
        ]);

        $this->assertSame('offline', $issued['licence']->enforcement);
        $this->postJson('/api/pos/licence/activate', ['key' => $issued['key']])
            ->assertOk()
            ->assertJsonPath('enforcement', 'offline');

        $this->actingAs($this->superAdmin)
            ->getJson("/api/admin/pos/licences/{$issued['licence']->id}/terminals")
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_the_terminals_view_lists_the_licence_tenants_tills_only(): void
    {
        $licence = $this->issue();
        ['token' => $token] = $this->claimTerminal();
        $this->check($token);

        $other = Restaurant::factory()->create();
        $branch = new Branch(['name_en' => 'Zamalek', 'code' => 'ZAM']);
        $branch->restaurant_id = $other->id;
        $branch->save();
        $stranger = new PosTerminal(['name' => 'Elsewhere']);
        $stranger->forceFill([
            'restaurant_id' => $other->id, 'branch_id' => $branch->id,
            'terminal_id' => 'other-1', 'state' => 'provisioned',
        ])->save();

        $this->actingAs($this->superAdmin)
            ->getJson("/api/admin/pos/licences/{$licence->id}/terminals")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.licence_id', $licence->id);
    }

    public function test_status_actions_are_super_admin_only(): void
    {
        $licence = $this->issue();

        $this->actingAs($this->owner)
            ->postJson("/api/admin/pos/licences/{$licence->id}/suspend")
            ->assertForbidden();
    }
}
