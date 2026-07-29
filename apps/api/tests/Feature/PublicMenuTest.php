<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\MenuViewDaily;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PublicMenuTest extends TestCase
{
    use RefreshDatabase;

    /** A realistic mobile-browser user-agent — the diner path. */
    private const BROWSER_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

    private function menuViews(int $restaurantId): int
    {
        $row = MenuViewDaily::withoutGlobalScopes()
            ->where('restaurant_id', $restaurantId)
            ->whereDate('date', now()->toDateString())
            ->first();

        return $row?->views ?? 0;
    }

    public function test_active_restaurant_menu_is_available(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'open']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/open/menu')
            ->assertOk()
            ->assertJsonPath('available', true)
            ->assertJsonCount(1, 'data.categories');
    }

    public function test_suspended_restaurant_menu_is_unavailable(): void
    {
        $r = Restaurant::factory()->suspended()->create(['slug' => 'closed']);

        $this->getJson('/api/public/restaurants/closed/menu')
            ->assertOk()
            ->assertJsonPath('available', false);

        // Legacy web path: with a menu domain the canonical URL is the
        // subdomain (302); without one it serves the SPA shell directly,
        // marked noindex because the restaurant is hidden.
        config(['platform.menu_domain' => 'xorder.io', 'platform.menu_secure' => true, 'platform.menu_port' => null]);
        $this->get('/r/closed')->assertRedirect('https://closed.xorder.io/menu');

        config(['platform.menu_domain' => null, 'platform.menu_shell_path' => base_path('tests/Fixtures/menu-shell.html')]);
        $this->get('/r/closed')->assertOk()->assertSee('noindex', false);
    }

    public function test_inactive_and_empty_categories_are_hidden(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'hide']);
        // inactive category with an item -> hidden
        $inactive = Category::factory()->for($r)->create(['is_active' => false]);
        MenuItem::factory()->for($r)->for($inactive)->create();
        // active but empty category -> hidden
        Category::factory()->for($r)->create(['is_active' => true, 'name_en' => 'Empty']);
        // active with item -> shown
        $shown = Category::factory()->for($r)->create(['is_active' => true, 'name_en' => 'Shown']);
        MenuItem::factory()->for($r)->for($shown)->create();

        $this->getJson('/api/public/restaurants/hide/menu')
            ->assertOk()
            ->assertJsonCount(1, 'data.categories')
            ->assertJsonPath('data.categories.0.name_en', 'Shown');
    }

    public function test_unavailable_items_are_still_listed(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'badge']);
        $cat = Category::factory()->for($r)->create();
        MenuItem::factory()->for($r)->for($cat)->unavailable()->create();

        $this->getJson('/api/public/restaurants/badge/menu')
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.is_available', false);
    }

    public function test_diner_menu_fetch_records_a_daily_view(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'counted']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->withHeader('User-Agent', self::BROWSER_UA)
            ->getJson('/api/public/restaurants/counted/menu')->assertOk();
        $this->withHeader('User-Agent', self::BROWSER_UA)
            ->getJson('/api/public/restaurants/counted/menu')->assertOk();

        $this->assertSame(2, $this->menuViews($r->id));
    }

    public function test_owner_preview_does_not_record_a_view(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'preview-me']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        // The admin "view my live menu" links open the menu with ?preview=1.
        $this->withHeader('User-Agent', self::BROWSER_UA)
            ->getJson('/api/public/restaurants/preview-me/menu?preview=1')->assertOk();

        $this->assertSame(0, $this->menuViews($r->id));
    }

    public function test_crawler_and_ualess_requests_do_not_record_a_view(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'crawled']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        // Link-preview bot, search crawler, and a bare script (no UA).
        $this->withHeader('User-Agent', 'facebookexternalhit/1.1')
            ->getJson('/api/public/restaurants/crawled/menu')->assertOk();
        $this->withHeader('User-Agent', 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)')
            ->getJson('/api/public/restaurants/crawled/menu')->assertOk();
        $this->withHeader('User-Agent', 'curl/8.4.0')
            ->getJson('/api/public/restaurants/crawled/menu')->assertOk();

        $this->assertSame(0, $this->menuViews($r->id));
    }

    public function test_unknown_slug_returns_404(): void
    {
        $this->getJson('/api/public/restaurants/nope/menu')->assertNotFound();
    }

    public function test_sitemap_lists_visible_restaurants_only(): void
    {
        config(['platform.menu_domain' => 'xorder.io', 'platform.menu_secure' => true, 'platform.menu_port' => null]);
        Restaurant::factory()->create(['slug' => 'visible']);
        Restaurant::factory()->suspended()->create(['slug' => 'hidden']);

        $res = $this->get('/sitemap.xml');

        $res->assertOk();
        $this->assertStringContainsString('application/xml', $res->headers->get('content-type'));
        $res->assertSee('https://visible.xorder.io/menu', false);
        $res->assertDontSee('https://hidden.xorder.io/menu', false);
    }

    public function test_public_payload_excludes_internal_fields(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'priv']);
        $cat = Category::factory()->for($r)->create();
        MenuItem::factory()->for($r)->for($cat)->create();

        $res = $this->getJson('/api/public/restaurants/priv/menu')->assertOk();
        $restaurant = $res->json('data.restaurant');

        $this->assertArrayNotHasKey('subscription_status', $restaurant);
        $this->assertArrayNotHasKey('status', $restaurant);
    }
}
