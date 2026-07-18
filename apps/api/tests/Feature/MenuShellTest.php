<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MenuShellTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['platform.menu_shell_path' => base_path('tests/Fixtures/menu-shell.html')]);
    }

    public function test_menu_shell_injects_restaurant_seo_meta(): void
    {
        $restaurant = Restaurant::factory()->create([
            'slug' => 'demo',
            'name_ar' => 'مطعم التجربة',
            'name_en' => 'Demo Restaurant',
            'description_ar' => 'أفضل مطعم',
            'logo_url' => '/storage/logos/demo.webp',
        ]);

        $res = $this->get('http://demo.xorder.io/menu');

        $res->assertOk();
        // default_language is AR in the factory → Arabic name leads.
        $res->assertSee('<title>مطعم التجربة</title>', false);
        $res->assertSee('og:title', false);
        $res->assertSee('og:type" content="restaurant.menu', false);
        $res->assertSee('application/ld+json', false);
        $res->assertSee('"@type":"Restaurant"', false);
        $res->assertSee('lang="ar" dir="rtl"', false);
        // The restaurant's logo becomes the browser-tab favicon (resolved to an absolute URL).
        $res->assertSee('rel="icon" href="http://', false);
        $res->assertSee('/storage/logos/demo.webp">', false);
        $res->assertSee('rel="apple-touch-icon"', false);
        // The SPA markup itself is intact.
        $res->assertSee('<div id="app"></div>', false);
    }

    public function test_unknown_slug_serves_noindex_shell_with_404(): void
    {
        $res = $this->get('http://nope.xorder.io/menu');

        $res->assertNotFound();
        $res->assertSee('robots" content="noindex', false);
        $res->assertSee('<div id="app"></div>', false);
    }

    public function test_hidden_restaurant_gets_noindex_but_renders(): void
    {
        Restaurant::factory()->suspended()->create(['slug' => 'closed']);

        $res = $this->get('http://closed.xorder.io/menu');

        $res->assertOk();
        $res->assertSee('robots" content="noindex', false);
    }

    public function test_legacy_path_redirects_to_subdomain_when_menu_domain_set(): void
    {
        config(['platform.menu_domain' => 'xorder.io', 'platform.menu_secure' => true, 'platform.menu_port' => null]);
        Restaurant::factory()->create(['slug' => 'demo']);

        $this->get('/r/demo')
            ->assertRedirect('https://demo.xorder.io/menu');
    }

    public function test_legacy_path_serves_shell_without_menu_domain(): void
    {
        config(['platform.menu_domain' => null]);
        Restaurant::factory()->create(['slug' => 'demo', 'name_ar' => 'مطعمي']);

        $res = $this->get('/r/demo');

        $res->assertOk();
        $res->assertSee('og:title', false);
    }

    public function test_legacy_path_unknown_slug_is_404(): void
    {
        $this->get('/r/ghost')->assertNotFound();
    }
}
