<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the owner's
 * "Counter QR" in the dashboard.
 */
class PagerQrTest extends TestCase
{
    use RefreshDatabase;

    private function owner(string $slug, bool $paging = true): User
    {
        $restaurant = Restaurant::factory()->create(['slug' => $slug]);
        $restaurant->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => $paging]);

        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    public function test_the_owner_gets_the_standing_qr_for_the_join_page(): void
    {
        config(['platform.menu_domain' => 'xorder.io', 'platform.menu_secure' => true]);
        $owner = $this->owner('demo');

        $res = $this->actingAs($owner)->getJson('/api/dashboard/pager-qr')->assertOk();

        // The restaurant's own host, and the path the server already routes to the menu app.
        $this->assertSame('https://demo.xorder.io/menu/p', $res->json('data.join_url'));
        $this->assertStringContainsString('<svg', $res->json('data.svg'));
    }

    public function test_without_a_menu_domain_it_falls_back_to_the_path_form_used_in_development(): void
    {
        config(['platform.menu_domain' => null]);

        $res = $this->actingAs($this->owner('demo'))->getJson('/api/dashboard/pager-qr')->assertOk();

        $this->assertStringEndsWith('/r/demo/p', $res->json('data.join_url'));
    }

    public function test_each_restaurant_only_ever_gets_its_own_qr(): void
    {
        $a = $this->owner('alpha');
        $b = $this->owner('bravo');

        $this->assertStringContainsString('alpha', $this->actingAs($a)->getJson('/api/dashboard/pager-qr')->json('data.join_url'));
        $this->assertStringContainsString('bravo', $this->actingAs($b)->getJson('/api/dashboard/pager-qr')->json('data.join_url'));
    }

    public function test_it_needs_the_plan_feature_and_a_login(): void
    {
        $off = $this->owner('nopager', paging: false);

        $this->actingAs($off)->getJson('/api/dashboard/pager-qr')->assertForbidden();
        $this->actingAs($off)->getJson('/api/dashboard/pager-qr/download')->assertForbidden();

        $this->app['auth']->forgetGuards();
        $this->getJson('/api/dashboard/pager-qr')->assertUnauthorized();
    }

    public function test_the_png_download_is_named_after_the_restaurant(): void
    {
        if (! extension_loaded('imagick')) {
            $this->markTestSkipped('PNG QR codes need the imagick extension.');
        }

        $res = $this->actingAs($this->owner('demo'))->get('/api/dashboard/pager-qr/download')->assertOk();

        $res->assertHeader('Content-Type', 'image/png');
        $this->assertStringContainsString('qr-counter-demo.png', $res->headers->get('Content-Disposition'));
    }
}
