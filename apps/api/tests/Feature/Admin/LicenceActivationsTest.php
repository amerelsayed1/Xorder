<?php

namespace Tests\Feature\Admin;

use App\Models\PosLicence;
use App\Models\PosLicenceActivation;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * An offline customer has no tenant and no terminals on this platform, so the
 * licence page had nothing to say about whether the key had ever reached a
 * machine. These tests pin the record that now answers it: which device used the
 * key, when, and how many times, kept across a renewal.
 */
class LicenceActivationsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $pair = sodium_crypto_sign_keypair();
        config([
            'licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair)),
            'licence.key_id' => 'v1',
        ]);
    }

    private function admin(): User
    {
        return User::factory()->superAdmin()->create();
    }

    private function offline(array $overrides = []): array
    {
        return $this->actingAs($this->admin())->postJson('/api/admin/pos/licences/offline', array_merge([
            'customer_name' => 'Al Asima Grill',
            'customer_slug' => 'al-asima',
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 2,
        ], $overrides))->assertCreated()->json();
    }

    private function activate(string $key, ?string $fingerprint = null)
    {
        return $this->postJson('/api/pos/licence/activate', array_filter(['key' => $key, 'fingerprint' => $fingerprint]));
    }

    private function activations(array $licence)
    {
        return $this->actingAs($this->admin())->getJson("/api/admin/pos/licences/{$licence['data']['id']}/activations");
    }

    public function test_a_key_nobody_has_used_shows_no_devices(): void
    {
        $licence = $this->offline();

        $this->activations($licence)->assertOk()
            ->assertJsonPath('data', [])
            ->assertJsonPath('activated_at', null);
    }

    public function test_a_device_that_uses_the_key_is_recorded(): void
    {
        $licence = $this->offline();

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $response = $this->activations($licence)->assertOk();
        $response->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.fingerprint', 'fp-till-1')
            ->assertJsonPath('data.0.reported', true)
            ->assertJsonPath('data.0.times', 1);
        $this->assertNotNull($response->json('activated_at'));
        $this->assertNotNull($response->json('data.0.first_seen_at'));
    }

    public function test_the_same_device_again_moves_last_seen_and_the_count_not_the_row(): void
    {
        $licence = $this->offline();

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->travel(2)->days();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $row = $this->activations($licence)->assertOk()->assertJsonCount(1, 'data')->json('data.0');
        $this->assertSame(2, $row['times']);
        $this->assertNotSame($row['first_seen_at'], $row['last_seen_at']);
        $this->assertSame(1, PosLicenceActivation::count());
    }

    public function test_each_device_is_its_own_row_newest_first(): void
    {
        $licence = $this->offline();

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->travel(1)->hours();
        $this->activate($licence['activation_key'], 'fp-till-2')->assertOk();

        $this->activations($licence)->assertOk()
            ->assertJsonPath('data.0.fingerprint', 'fp-till-2')
            ->assertJsonPath('data.1.fingerprint', 'fp-till-1');
    }

    public function test_a_till_that_reports_no_fingerprint_is_one_unknown_device(): void
    {
        $licence = $this->offline();

        $this->activate($licence['activation_key'])->assertOk();
        $this->activate($licence['activation_key'])->assertOk();

        $this->activations($licence)->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.reported', false)
            ->assertJsonPath('data.0.times', 2);
    }

    public function test_a_renewal_that_keeps_the_key_keeps_the_history(): void
    {
        $licence = $this->offline();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $renewal = $this->actingAs($this->admin())
            ->postJson("/api/admin/pos/licences/{$licence['data']['id']}/renew", ['issued_at' => '2027-09-01', 'expires_at' => '2028-09-01'])
            ->assertCreated()->json();

        $this->activations($renewal)->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.fingerprint', 'fp-till-1');
    }

    public function test_a_rotated_key_starts_a_new_history(): void
    {
        $licence = $this->offline();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $renewal = $this->actingAs($this->admin())
            ->postJson("/api/admin/pos/licences/{$licence['data']['id']}/renew", [
                'issued_at' => '2027-09-01', 'expires_at' => '2028-09-01', 'rotate_key' => true,
            ])->assertCreated()->json();

        $this->activations($renewal)->assertOk()->assertJsonPath('data', []);
    }

    public function test_it_says_whether_a_device_is_on_the_locked_list(): void
    {
        $licence = $this->offline(['fingerprints' => ['fp-till-1']]);

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-stranger')->assertOk();

        $rows = collect($this->activations($licence)->assertOk()->assertJsonPath('locked', true)->json('data'))
            ->keyBy('fingerprint');
        $this->assertTrue($rows['fp-till-1']['pinned']);
        $this->assertFalse($rows['fp-stranger']['pinned']);
    }

    public function test_an_unlocked_licence_has_no_pinned_answer(): void
    {
        $licence = $this->offline();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $this->activations($licence)->assertOk()
            ->assertJsonPath('locked', false)
            ->assertJsonPath('data.0.pinned', null);
    }

    public function test_a_failed_activation_records_no_device(): void
    {
        $this->offline();

        $this->activate('XO-NOT-A-REAL-KEY', 'fp-till-1')->assertNotFound();

        $this->assertSame(0, PosLicenceActivation::count());
    }

    public function test_an_activation_still_succeeds_if_recording_the_device_fails(): void
    {
        $licence = $this->offline();
        Schema::drop('pos_licence_activations');

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $this->assertNotNull(PosLicence::sole()->activated_at, 'the till was still licensed');
    }

    public function test_only_a_super_admin_holding_licences_manage_can_read_it(): void
    {
        $licence = $this->offline();
        $owner = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($owner)->getJson("/api/admin/pos/licences/{$licence['data']['id']}/activations")->assertForbidden();

        // And nobody signed in at all.
        Auth::forgetGuards();
        $this->getJson("/api/admin/pos/licences/{$licence['data']['id']}/activations", ['Authorization' => ''])->assertUnauthorized();
    }

    // ------------------------------------------------- a licence for N devices

    public function test_a_one_device_licence_refuses_a_second_device(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $this->activate($licence['activation_key'], 'fp-till-2')
            ->assertStatus(409)
            ->assertJsonPath('code', 'licence_seats_full')
            ->assertJsonPath('seats', 1);

        // The refused device is not recorded, and it was not handed the file.
        $this->activations($licence)->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.fingerprint', 'fp-till-1')
            ->assertJsonPath('seats_enforced', true)
            ->assertJsonPath('seats', 1)
            ->assertJsonPath('in_use', 1);
    }

    public function test_the_first_device_can_always_come_back(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);

        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        // A renewal reaches a till by re-fetching under the same key.
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $this->assertSame(3, PosLicenceActivation::sole()->times);
    }

    public function test_a_licence_for_three_devices_takes_three_and_refuses_the_fourth(): void
    {
        $licence = $this->offline(['max_terminals' => 3]);

        foreach (['a', 'b', 'c'] as $d) {
            $this->activate($licence['activation_key'], "fp-$d")->assertOk();
        }
        $this->activate($licence['activation_key'], 'fp-d')->assertStatus(409)->assertJsonPath('code', 'licence_seats_full');
        $this->activate($licence['activation_key'], 'fp-b')->assertOk();

        $this->assertSame(3, PosLicenceActivation::count());
    }

    public function test_a_device_that_reports_no_id_counts_as_one_device(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);

        $this->activate($licence['activation_key'])->assertOk();
        $this->activate($licence['activation_key'])->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertStatus(409);
    }

    public function test_releasing_the_old_device_frees_the_seat_for_the_new_one(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);
        $this->activate($licence['activation_key'], 'fp-old')->assertOk();
        $this->activate($licence['activation_key'], 'fp-new')->assertStatus(409);

        $id = $this->activations($licence)->json('data.0.id');
        $this->actingAs($this->admin())
            ->deleteJson("/api/admin/pos/licences/{$licence['data']['id']}/activations/{$id}")
            ->assertOk();

        $this->activate($licence['activation_key'], 'fp-new')->assertOk();
        $this->activations($licence)->assertJsonCount(1, 'data')->assertJsonPath('data.0.fingerprint', 'fp-new');
    }

    public function test_an_upgrade_renewal_makes_room_and_keeps_the_devices_already_in(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-2')->assertStatus(409);

        $this->actingAs($this->admin())
            ->postJson("/api/admin/pos/licences/{$licence['data']['id']}/renew", [
                'issued_at' => '2027-09-01', 'expires_at' => '2028-09-01', 'max_terminals' => 2,
            ])->assertCreated();

        $this->activate($licence['activation_key'], 'fp-till-2')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-3')->assertStatus(409);
    }

    public function test_a_downgrade_never_locks_out_a_device_already_in(): void
    {
        $licence = $this->offline(['max_terminals' => 2]);
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-2')->assertOk();

        $this->actingAs($this->admin())
            ->postJson("/api/admin/pos/licences/{$licence['data']['id']}/renew", [
                'issued_at' => '2027-09-01', 'expires_at' => '2028-09-01', 'max_terminals' => 1,
            ])->assertCreated();

        // Both are still known, so both still get their file; no third is let in.
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-2')->assertOk();
        $this->activate($licence['activation_key'], 'fp-till-3')->assertStatus(409);
    }

    public function test_a_cloud_licence_is_not_held_to_a_device_count(): void
    {
        $restaurant = Restaurant::factory()->create(['slug' => 'demo']);
        $cloud = $this->actingAs($this->admin())->postJson('/api/admin/pos/licences', [
            'restaurant_id' => $restaurant->id,
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 1,
            'modes' => ['cloud'],
        ])->assertCreated()->json();

        // Their tills share one key by design, and their limit has never been
        // counted: refusing now would break tills that work today.
        $this->activate($cloud['activation_key'], 'fp-till-1')->assertOk();
        $this->activate($cloud['activation_key'], 'fp-till-2')->assertOk();

        $this->activations($cloud)->assertJsonPath('seats_enforced', false)->assertJsonCount(2, 'data');
    }

    public function test_a_refused_device_gets_a_sentence_in_the_customers_language(): void
    {
        $licence = $this->offline(['max_terminals' => 1]);
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();

        $message = $this->activate($licence['activation_key'], 'fp-till-2')->assertStatus(409)->json('message');
        $this->assertStringNotContainsString('xorder.errors', $message, 'a real sentence, not a translation key');
        $this->assertStringContainsString('1', $message);
    }

    public function test_a_device_cannot_be_released_from_another_licences_key(): void
    {
        $mine = $this->offline(['max_terminals' => 1]);
        $this->activate($mine['activation_key'], 'fp-till-1')->assertOk();

        $other = $this->offline(['customer_slug' => 'other-cafe', 'max_terminals' => 1]);
        $id = $this->activations($mine)->json('data.0.id');

        $this->actingAs($this->admin())
            ->deleteJson("/api/admin/pos/licences/{$other['data']['id']}/activations/{$id}")
            ->assertNotFound();
        $this->assertSame(1, PosLicenceActivation::count());
    }

    public function test_only_a_super_admin_may_release_a_device(): void
    {
        $licence = $this->offline();
        $this->activate($licence['activation_key'], 'fp-till-1')->assertOk();
        $id = $this->activations($licence)->json('data.0.id');
        $owner = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($owner)
            ->deleteJson("/api/admin/pos/licences/{$licence['data']['id']}/activations/{$id}")
            ->assertForbidden();
        $this->assertSame(1, PosLicenceActivation::count());
    }
}
