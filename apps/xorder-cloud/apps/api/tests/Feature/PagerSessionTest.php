<?php

namespace Tests\Feature;

use App\Models\PagerSession;
use App\Models\Restaurant;
use App\Services\PagerSessionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Tests\TestCase;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the join page's
 * side. The till's side (peek, pager_code on an order) is in Pos/PosPagerTest.
 */
class PagerSessionTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant = $this->restaurantWithPaging('demo');
    }

    private function restaurantWithPaging(string $slug, bool $paging = true): Restaurant
    {
        $r = Restaurant::factory()->create(['slug' => $slug]);
        $r->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => $paging]);

        return $r;
    }

    private function start(string $slug = 'demo', ?string $secret = null)
    {
        return $this->postJson("/api/public/restaurants/{$slug}/pager-sessions", [], $secret ? ['X-Pager-Secret' => $secret] : []);
    }

    private function current(string $secret, string $slug = 'demo')
    {
        return $this->getJson("/api/public/restaurants/{$slug}/pager-sessions/current", ['X-Pager-Secret' => $secret]);
    }

    // AC-1
    public function test_scanning_opens_a_session_with_a_short_code_and_a_secret_shown_once(): void
    {
        $res = $this->start()->assertCreated();

        $this->assertMatchesRegularExpression('/^\d{4}$/', $res->json('data.code'));
        $this->assertSame(40, strlen($res->json('data.secret')));
        $res->assertJsonPath('data.state', 'open');
        $res->assertHeader('Cache-Control', 'no-store, private');
        $this->assertSame(
            ['name', 'name_ar', 'name_en', 'default_language', 'bilingual', 'logo_url', 'brand_color'],
            array_keys($res->json('data.restaurant')),
        );

        // Only the hash of the secret is stored.
        $row = PagerSession::query()->firstOrFail();
        $this->assertNotSame($res->json('data.secret'), $row->secret_hash);
        $this->assertSame(hash('sha256', $res->json('data.secret')), $row->secret_hash);
        $this->assertSame($this->restaurant->id, $row->restaurant_id);
    }

    // AC-9
    public function test_scanning_again_with_the_same_secret_gets_the_same_code_and_no_new_secret(): void
    {
        $first = $this->start()->assertCreated();

        $again = $this->start('demo', $first->json('data.secret'))->assertOk();

        $this->assertSame($first->json('data.code'), $again->json('data.code'));
        $this->assertArrayNotHasKey('secret', $again->json('data'));
        $this->assertSame(1, PagerSession::query()->count());
    }

    // AC-10
    public function test_clients_get_different_codes(): void
    {
        $codes = [];
        for ($i = 0; $i < 30; $i++) {
            $codes[] = $this->start()->assertCreated()->json('data.code');
        }

        $this->assertCount(30, array_unique($codes));
    }

    // AC-11
    public function test_a_session_is_readable_only_with_its_own_secret(): void
    {
        $secret = $this->start()->json('data.secret');

        $this->current($secret)->assertOk()->assertJsonPath('data.state', 'open');

        $this->current(str_repeat('x', 40))->assertNotFound();
        $this->getJson('/api/public/restaurants/demo/pager-sessions/current')->assertNotFound();
        $this->current('short')->assertNotFound();
    }

    public function test_one_restaurants_secret_means_nothing_to_another_restaurant(): void
    {
        $this->restaurantWithPaging('other');
        $secret = $this->start()->json('data.secret');

        $this->current($secret, 'other')->assertNotFound();
    }

    // AC-15
    public function test_it_is_not_available_without_the_feature_or_for_an_unknown_restaurant(): void
    {
        $this->restaurantWithPaging('nopager', paging: false);

        $this->start('nopager')->assertForbidden();
        $this->start('nobody')->assertNotFound();
        $this->assertSame(0, PagerSession::query()->count());
    }

    public function test_an_expired_code_reads_expired_and_a_new_scan_replaces_it(): void
    {
        $first = $this->start()->json('data');
        PagerSession::query()->update(['expires_at' => now()->subMinute()]);

        $this->current($first['secret'])->assertOk()->assertJsonPath('data.state', 'expired');

        $fresh = $this->start('demo', $first['secret'])->assertCreated();
        $this->assertNotSame($first['secret'], $fresh->json('data.secret'));
        $this->assertSame(1, PagerSession::query()->count(), 'the dead row is gone, its number free');
    }

    // AC-14
    public function test_starting_sessions_is_rate_limited_per_address(): void
    {
        for ($i = 0; $i < 120; $i++) {
            $this->start()->assertCreated();
        }

        $this->start()->assertStatus(429);
        $this->assertSame(120, PagerSession::query()->count(), 'the refused call created nothing');
    }

    public function test_a_code_is_freed_the_moment_it_is_bound(): void
    {
        $service = app(PagerSessionService::class);
        $code = $this->start()->json('data.code');

        // Bound sessions keep no code, so the same number can be issued again.
        PagerSession::query()->update(['code' => null, 'bound_at' => now()]);

        $this->assertFalse($service->peek($this->restaurant, $code));
        $this->assertSame(1, PagerSession::query()->whereNull('code')->count());
    }

    public function test_the_prune_job_removes_only_dead_sessions(): void
    {
        $live = $this->start()->json('data.secret');

        $dead = new PagerSession;
        $dead->forceFill([
            'restaurant_id' => $this->restaurant->id, 'code' => '9999',
            'secret_hash' => hash('sha256', 'dead'), 'expires_at' => now()->subHours(3),
        ])->save();

        $old = new PagerSession;
        $old->forceFill([
            'restaurant_id' => $this->restaurant->id, 'code' => null,
            'secret_hash' => hash('sha256', 'old'), 'expires_at' => now()->subDays(5),
            'bound_at' => now()->subDays(3),
        ])->save();

        Artisan::call('pager:prune');

        $this->assertSame(1, PagerSession::query()->count());
        $this->current($live)->assertOk();
    }
}
