<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
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

    public function test_menu_shell_serves_whatsapp_friendly_derivatives(): void
    {
        Storage::fake('public');
        $png = $this->fakePng(600, 400);
        Storage::disk('public')->put('covers/demo.webp', $png);
        Storage::disk('public')->put('logos/demo.webp', $png);

        Restaurant::factory()->create([
            'slug' => 'demo',
            'name_en' => 'Demo Restaurant',
            'logo_url' => '/storage/logos/demo.webp',
            'cover_image_url' => '/storage/covers/demo.webp',
        ]);

        $res = $this->get('http://demo.xorder.io/menu');

        $res->assertOk();
        // OG image is a generated JPEG (WhatsApp/iMessage can't render WebP).
        $res->assertSee('brand-cache/demo-og.jpg', false);
        $res->assertSee('og:image:type" content="image/jpeg', false);
        $res->assertSee('og:image:width" content="600', false);
        $res->assertSee('twitter:card" content="summary_large_image', false);
        // Favicon is the PNG derivative; the generic Xorder icons are removed.
        $res->assertSee('brand-cache/demo-icon.png', false);
        $res->assertDontSee('favicon.svg', false);
        $res->assertDontSee('favicon-32.png', false);
        // No raw .webp survives in any icon/OG tag.
        $res->assertDontSee('/storage/covers/demo.webp', false);
        $res->assertDontSee('/storage/logos/demo.webp', false);

        Storage::disk('public')->assertExists('brand-cache/demo-og.jpg');
        Storage::disk('public')->assertExists('brand-cache/demo-icon.png');
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

    /** Raw PNG bytes for a solid image of the given size (decodable by GD/Imagick). */
    private function fakePng(int $width, int $height): string
    {
        $image = imagecreatetruecolor($width, $height);
        imagefill($image, 0, 0, imagecolorallocate($image, 200, 120, 40));
        ob_start();
        imagepng($image);
        $bytes = ob_get_clean();
        imagedestroy($image);

        return $bytes;
    }
}
