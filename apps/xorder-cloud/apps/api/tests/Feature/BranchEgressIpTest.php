<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\BranchEgressIpService;
use App\Support\EgressIp;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The learned "is this diner on the branch's customer Wi-Fi?" signal.
 *
 * The browser cannot report which network it is joined to, so this is derived
 * entirely server-side from the address requests arrive from, and learned from
 * sessions the geofence already proved were on-premises.
 */
class BranchEgressIpTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Branch $branch;

    private DiningArea $area;

    /**
     * The branch's own line, as the server sees it — i.e. the single address a
     * shop's NAT presents to us. Reserved documentation ranges (RFC 5737) so no
     * real subscriber's address is baked into the repo.
     */
    private const SHOP_IP = '203.0.113.10';

    /** A diner on mobile data — a different carrier address entirely. */
    private const MOBILE_IP = '198.51.100.42';

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'bistro']);
        $this->branch = new Branch(['name_en' => 'Downtown']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();
        $this->area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Outdoor']);
        $this->area->restaurant_id = $this->restaurant->id;
        $this->area->save();
    }

    private function makeTable(string $label = '12'): DiningTable
    {
        $t = new DiningTable([
            'dining_area_id' => $this->area->id, 'label' => $label,
            'public_token' => DiningTable::generateToken(), 'is_active' => true,
            'qr_generated_at' => now(),
        ]);
        $t->restaurant_id = $this->restaurant->id;
        $t->branch_id = $this->branch->id;
        $t->save();

        return $t;
    }

    /** A 200 m radius fence around (30.00, 31.00). */
    private function enableFence(): void
    {
        // Learning is fed by geofence-verified sessions, so these tests need
        // enforcement on even though it ships switched off.
        config(['platform.presence.geofence_enforcement' => true]);
        $this->branch->update([
            'geofence_enabled' => true,
            'geofence' => ['type' => 'radius', 'center' => ['lat' => 30.0, 'lng' => 31.0], 'radius' => 200],
        ]);
    }

    /** Open a session from $ip, with an in-fence fix by default. */
    private function scan(DiningTable $table, string $ip, array $payload = ['latitude' => 30.0, 'longitude' => 31.0, 'accuracy' => 20])
    {
        return $this->withServerVariables(['REMOTE_ADDR' => $ip])
            ->postJson("/api/public/tables/{$table->public_token}/sessions", $payload);
    }

    // ── Evidence capture ───────────────────────────────────────────────────

    public function test_session_records_the_source_ip_and_the_fix_that_admitted_it(): void
    {
        $this->enableFence();
        $table = $this->makeTable();

        $token = $this->scan($table, self::SHOP_IP)->assertCreated()->json('data.session_token');

        $this->assertDatabaseHas('menu_sessions', [
            'session_token' => $token,
            'client_ip' => self::SHOP_IP,
            'accuracy_m' => 20,
            'presence_source' => MenuSession::PRESENCE_GEOFENCE,
        ]);

        $session = MenuSession::withoutGlobalScopes()->where('session_token', $token)->firstOrFail();
        $this->assertEqualsWithDelta(30.0, $session->latitude, 0.0000001);
        $this->assertEqualsWithDelta(31.0, $session->longitude, 0.0000001);
    }

    public function test_presence_source_is_null_when_the_branch_has_no_fence_to_verify_against(): void
    {
        $table = $this->makeTable();

        // No fence: the IP is still recorded, but nothing vouched for presence,
        // so this session must never be used to teach an egress address.
        $token = $this->scan($table, self::SHOP_IP, [])->assertCreated()->json('data.session_token');

        $this->assertDatabaseHas('menu_sessions', [
            'session_token' => $token,
            'client_ip' => self::SHOP_IP,
            'presence_source' => null,
        ]);
    }

    public function test_match_is_unknown_rather_than_false_before_anything_is_learned(): void
    {
        $this->enableFence();
        $table = $this->makeTable();

        $token = $this->scan($table, self::SHOP_IP)->assertCreated()->json('data.session_token');

        $session = MenuSession::withoutGlobalScopes()->where('session_token', $token)->firstOrFail();
        $this->assertNull($session->on_branch_network, 'No learned IPs yet — the question is unanswerable, not answered "no".');
    }

    // ── Learning ───────────────────────────────────────────────────────────

    public function test_it_learns_the_address_repeated_verified_sessions_arrive_from(): void
    {
        config(['platform.presence.egress_min_sessions' => 3]);
        $this->enableFence();
        $table = $this->makeTable();

        for ($i = 0; $i < 3; $i++) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        // One diner on mobile data — below the threshold, so not the shop's line.
        $this->scan($table, self::MOBILE_IP)->assertCreated();

        $learned = app(BranchEgressIpService::class)->learn($this->branch->fresh());

        $this->assertSame([self::SHOP_IP], $learned);
        $this->assertSame([self::SHOP_IP], $this->branch->fresh()->egress_ips);
        $this->assertNotNull($this->branch->fresh()->egress_ips_learned_at);
    }

    public function test_it_ignores_sessions_no_fence_ever_verified(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $table = $this->makeTable();

        // Fence off: plenty of sessions from one address, none of them proof of
        // presence. Learning from these would teach whatever IP recurs.
        for ($i = 0; $i < 5; $i++) {
            $this->scan($table, self::MOBILE_IP, [])->assertCreated();
        }

        $this->assertSame([], app(BranchEgressIpService::class)->learn($this->branch->fresh()));
        $this->assertNull($this->branch->fresh()->egress_ips);
    }

    public function test_it_ignores_verified_sessions_that_have_aged_out_of_the_window(): void
    {
        config(['platform.presence.egress_min_sessions' => 2, 'platform.presence.egress_learning_days' => 30]);
        $this->enableFence();
        $table = $this->makeTable();

        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        // Age both past the window — a rotated dynamic IP must fall away.
        MenuSession::withoutGlobalScopes()->update(['started_at' => now()->subDays(40)]);

        $this->assertSame([], app(BranchEgressIpService::class)->learn($this->branch->fresh()));
    }

    // ── Matching ───────────────────────────────────────────────────────────

    public function test_once_learned_a_scan_from_that_address_is_flagged_as_on_the_branch_network(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $this->enableFence();
        $table = $this->makeTable();

        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        app(BranchEgressIpService::class)->learn($this->branch->fresh());

        $onWifi = $this->scan($table, self::SHOP_IP)->assertCreated()->json('data.session_token');
        $onMobile = $this->scan($table, self::MOBILE_IP)->assertCreated()->json('data.session_token');

        $this->assertTrue(MenuSession::withoutGlobalScopes()->where('session_token', $onWifi)->value('on_branch_network'));
        $this->assertFalse((bool) MenuSession::withoutGlobalScopes()->where('session_token', $onMobile)->value('on_branch_network'));
    }

    public function test_a_non_matching_address_never_blocks_the_session(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $this->enableFence();
        $table = $this->makeTable();

        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        app(BranchEgressIpService::class)->learn($this->branch->fresh());

        // A diner sitting at the table on mobile data. The fence says they are
        // present; the IP says nothing. The fence must remain the authority.
        $this->scan($table, self::MOBILE_IP)
            ->assertCreated()
            ->assertJsonStructure(['data' => ['session_token']]);
    }

    public function test_the_learning_command_writes_the_branch_addresses(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $this->enableFence();
        $table = $this->makeTable();

        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }

        $this->artisan('branches:learn-egress-ips')->assertSuccessful();

        $this->assertSame([self::SHOP_IP], $this->branch->fresh()->egress_ips);
    }

    // ── Per-client dashboard reporting ─────────────────────────────────────

    private function admin(): User
    {
        return User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    public function test_the_presence_card_reports_the_fence_prerequisite_before_anything_else(): void
    {
        // Fence off: nothing can ever be learned, and the card must say so
        // rather than reporting a bare "not detected" the owner can't act on.
        $this->actingAs($this->admin())
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk()
            ->assertJsonPath('data.geofence_enabled', false)
            ->assertJsonPath('data.wifi_detected', false)
            ->assertJsonPath('data.on_wifi_rate', null);
    }

    public function test_the_presence_card_reports_the_share_of_scans_on_the_branch_wifi(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $this->enableFence();
        $table = $this->makeTable();

        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        app(BranchEgressIpService::class)->learn($this->branch->fresh());

        // Three more measurable scans: two on the shop Wi-Fi, one on mobile.
        $this->scan($table, self::SHOP_IP)->assertCreated();
        $this->scan($table, self::SHOP_IP)->assertCreated();
        $this->scan($table, self::MOBILE_IP)->assertCreated();

        $this->actingAs($this->admin())
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk()
            ->assertJsonPath('data.wifi_detected', true)
            ->assertJsonPath('data.measured_sessions', 3)
            ->assertJsonPath('data.on_wifi_sessions', 2)
            ->assertJsonPath('data.on_wifi_rate', 67);
    }

    public function test_the_rate_is_null_not_zero_while_no_session_could_be_measured(): void
    {
        $this->enableFence();
        $table = $this->makeTable();
        $this->scan($table, self::SHOP_IP)->assertCreated();

        // Nothing learned yet, so that session's match is unknown. Reporting 0%
        // here would read as a confident "nobody uses your Wi-Fi".
        $this->actingAs($this->admin())
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk()
            ->assertJsonPath('data.sessions', 1)
            ->assertJsonPath('data.measured_sessions', 0)
            ->assertJsonPath('data.on_wifi_rate', null);
    }

    public function test_the_card_never_leaks_the_learned_addresses(): void
    {
        config(['platform.presence.egress_min_sessions' => 1]);
        $this->enableFence();
        $this->scan($this->makeTable(), self::SHOP_IP)->assertCreated();
        app(BranchEgressIpService::class)->learn($this->branch->fresh());

        // Browse from somewhere else, so `your_ip` (which legitimately echoes
        // the caller's own address) can't be confused with a leak of the
        // learned list.
        $res = $this->actingAs($this->admin())
            ->withServerVariables(['REMOTE_ADDR' => self::MOBILE_IP])
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk();

        $res->assertJsonPath('data.learned', true)   // reported as a fact…
            ->assertJsonPath('data.manual_ips', []); // …but nothing declared

        $body = $res->getContent();
        $this->assertStringNotContainsString(self::SHOP_IP, $body, 'The learned address itself must never reach the client.');
        $this->assertStringNotContainsString('egress_ips', $body);
    }

    public function test_another_restaurant_cannot_read_this_branchs_presence(): void
    {
        $outsider = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($outsider)
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertNotFound();
    }

    // ── Declaring a connection by hand ─────────────────────────────────────

    private function putIps(array $ips)
    {
        return $this->actingAs($this->admin())
            ->putJson("/api/dashboard/branches/{$this->branch->id}/presence/egress-ips", ['egress_ips' => $ips]);
    }

    public function test_an_owner_can_declare_the_branch_connection_without_waiting_to_learn_it(): void
    {
        $this->enableFence();
        $table = $this->makeTable();

        $this->putIps([self::SHOP_IP])
            ->assertOk()
            ->assertJsonPath('data.manual_ips', [self::SHOP_IP])
            ->assertJsonPath('data.wifi_detected', true)
            // Declared, not learned — the two are reported separately.
            ->assertJsonPath('data.learned', false);

        // Takes effect immediately: no verified-session history at all.
        $token = $this->scan($table, self::SHOP_IP)->assertCreated()->json('data.session_token');
        $this->assertTrue(MenuSession::withoutGlobalScopes()->where('session_token', $token)->value('on_branch_network'));
    }

    public function test_the_dashboard_reports_the_address_the_admin_is_browsing_from(): void
    {
        // This is what powers "use this connection" — the owner never has to
        // look their public address up anywhere.
        $this->actingAs($this->admin())
            ->withServerVariables(['REMOTE_ADDR' => self::SHOP_IP])
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk()
            ->assertJsonPath('data.your_ip', self::SHOP_IP);
    }

    public function test_learning_never_overwrites_what_the_owner_declared(): void
    {
        config(['platform.presence.egress_min_sessions' => 2]);
        $this->enableFence();
        $table = $this->makeTable();

        $this->putIps([self::MOBILE_IP])->assertOk();

        // The branch then learns a different address on its own.
        foreach ([0, 1] as $_) {
            $this->scan($table, self::SHOP_IP)->assertCreated();
        }
        app(BranchEgressIpService::class)->learn($this->branch->fresh());

        $branch = $this->branch->fresh();
        $this->assertSame([self::MOBILE_IP], $branch->egress_ips_manual, 'The nightly job must not erase a declared address.');
        $this->assertSame([self::SHOP_IP], $branch->egress_ips);

        // Both are recognised.
        $service = app(BranchEgressIpService::class);
        $this->assertTrue($service->matches($branch, self::SHOP_IP));
        $this->assertTrue($service->matches($branch, self::MOBILE_IP));
    }

    public function test_declared_addresses_can_be_cleared(): void
    {
        $this->putIps([self::SHOP_IP])->assertOk();
        $this->putIps([])->assertOk()->assertJsonPath('data.manual_ips', [])->assertJsonPath('data.wifi_detected', false);

        $this->assertNull($this->branch->fresh()->egress_ips_manual);
    }

    public function test_junk_and_overlong_lists_are_rejected(): void
    {
        $this->putIps(['not-an-ip'])->assertStatus(422)->assertJsonValidationErrors('egress_ips.0');
        $this->putIps(['1.1.1.1', '1.1.1.2', '1.1.1.3', '1.1.1.4', '1.1.1.5', '1.1.1.6'])
            ->assertStatus(422)->assertJsonValidationErrors('egress_ips');

        $this->assertNull($this->branch->fresh()->egress_ips_manual);
    }

    public function test_another_restaurant_cannot_declare_addresses_on_this_branch(): void
    {
        $outsider = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($outsider)
            ->putJson("/api/dashboard/branches/{$this->branch->id}/presence/egress-ips", ['egress_ips' => [self::SHOP_IP]])
            ->assertNotFound();

        $this->assertNull($this->branch->fresh()->egress_ips_manual);
    }

    // ── Noticing the line has changed address ──────────────────────────────

    /** A third address — the one the branch's line rotated onto. */
    private const ROTATED_IP = '203.0.113.77';

    private function drift(): array
    {
        return app(BranchEgressIpService::class)->drift($this->branch->fresh());
    }

    public function test_it_flags_a_new_address_that_has_taken_over_the_branchs_scans(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 3]);
        $table = $this->makeTable();
        $this->putIps([self::SHOP_IP])->assertOk();

        // The line rotates: every scan now arrives from somewhere new.
        for ($i = 0; $i < 4; $i++) {
            $this->scan($table, self::ROTATED_IP, [])->assertCreated();
        }

        $drift = $this->drift();

        $this->assertSame(self::ROTATED_IP, $drift['suggested']['ip']);
        $this->assertSame(4, $drift['suggested']['sessions']);
        $this->assertSame(100, $drift['suggested']['share']);
        // …and the declared address is called out as matching nothing.
        $this->assertSame([self::SHOP_IP], $drift['stale']);
    }

    public function test_nothing_is_flagged_while_the_declared_address_still_carries_the_traffic(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 2]);
        $table = $this->makeTable();
        $this->putIps([self::SHOP_IP])->assertOk();

        for ($i = 0; $i < 5; $i++) {
            $this->scan($table, self::SHOP_IP, [])->assertCreated();
        }
        // One diner on mobile data, as always.
        $this->scan($table, self::MOBILE_IP, [])->assertCreated();

        $drift = $this->drift();

        $this->assertNull($drift['suggested'], 'Nothing changed — the owner must not be nagged.');
        $this->assertSame([], $drift['stale']);
    }

    public function test_a_scattering_of_mobile_diners_never_looks_like_a_changed_connection(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 2, 'platform.presence.egress_drift_min_share' => 60]);
        $table = $this->makeTable();
        $this->putIps([self::SHOP_IP])->assertOk();

        // Two different carrier addresses, neither dominant. This is the shape
        // of ordinary mobile traffic and must not be mistaken for a new line.
        foreach ([self::MOBILE_IP, self::MOBILE_IP, self::ROTATED_IP, self::ROTATED_IP] as $ip) {
            $this->scan($table, $ip, [])->assertCreated();
        }

        $this->assertNull($this->drift()['suggested']);
    }

    public function test_a_single_visitor_is_too_little_to_move_a_branch(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 5]);
        $table = $this->makeTable();
        $this->putIps([self::SHOP_IP])->assertOk();

        // 100% share, but only twice — below the session floor.
        $this->scan($table, self::ROTATED_IP, [])->assertCreated();
        $this->scan($table, self::ROTATED_IP, [])->assertCreated();

        $this->assertNull($this->drift()['suggested']);
    }

    public function test_a_branch_with_nothing_declared_is_not_told_its_connection_changed(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 2]);
        $table = $this->makeTable();

        for ($i = 0; $i < 4; $i++) {
            $this->scan($table, self::ROTATED_IP, [])->assertCreated();
        }

        // Nothing on file, so nothing has drifted — the ordinary "add your
        // connection" flow covers this, and guessing from traffic would be a
        // weaker route to the same result.
        $this->assertNull($this->drift()['suggested']);
    }

    public function test_the_dashboard_surfaces_the_suggestion(): void
    {
        config(['platform.presence.egress_drift_min_sessions' => 2]);
        $table = $this->makeTable();
        $this->putIps([self::SHOP_IP])->assertOk();

        for ($i = 0; $i < 3; $i++) {
            $this->scan($table, self::ROTATED_IP, [])->assertCreated();
        }

        $this->actingAs($this->admin())
            ->getJson("/api/dashboard/branches/{$this->branch->id}/presence")
            ->assertOk()
            ->assertJsonPath('data.drift.suggested.ip', self::ROTATED_IP)
            ->assertJsonPath('data.drift.stale', [self::SHOP_IP]);
    }

    // ── Address normalisation ──────────────────────────────────────────────

    public function test_ipv6_is_compared_on_the_network_prefix_not_the_rotating_host_half(): void
    {
        // Same line, two visits: SLAAC privacy extensions change the low half,
        // so only the /64 identifies the network.
        $this->assertSame(
            EgressIp::normalize('2001:db8:abcd:1234:1111:2222:3333:4444'),
            EgressIp::normalize('2001:db8:abcd:1234:aaaa:bbbb:cccc:dddd')
        );
        $this->assertSame('2001:db8:abcd:1234::/64', EgressIp::normalize('2001:db8:abcd:1234::1'));

        // A different delegated prefix is a different network.
        $this->assertNotSame(
            EgressIp::normalize('2001:db8:abcd:1234::1'),
            EgressIp::normalize('2001:db8:abcd:9999::1')
        );
    }

    public function test_ipv4_is_compared_exactly_and_junk_is_rejected(): void
    {
        $this->assertSame('203.0.113.10', EgressIp::normalize('203.0.113.10'));
        $this->assertNull(EgressIp::normalize(null));
        $this->assertNull(EgressIp::normalize(''));
        $this->assertNull(EgressIp::normalize('not-an-ip'));
    }
}
