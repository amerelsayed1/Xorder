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
        // The restaurant's logo becomes the browser-tab favicon, as a path so
        // the browser fetches it from the host it is already on rather than
        // opening a second connection to the apex APP_URL points at.
        $res->assertSee('rel="icon" href="/storage/logos/demo.webp"', false);
        $res->assertSee('rel="apple-touch-icon" href="/storage/logos/demo.webp"', false);
        // The SPA markup itself is intact.
        $res->assertSee('<div id="app"></div>', false);
    }

    public function test_arabic_restaurant_keeps_the_arabic_font_preloads(): void
    {
        Restaurant::factory()->create(['slug' => 'demo', 'name_ar' => 'مطعم', 'default_language' => 'ar']);

        $res = $this->get('http://demo.xorder.io/menu');

        $res->assertSee('/menu/fonts/tajawal-400-arabic.woff2', false);
        $res->assertSee('/menu/fonts/tajawal-700-arabic.woff2', false);
        // Prices are ASCII digits even here, and they are bold — the Latin
        // subset the shell preloads for them survives untouched.
        $res->assertSee('/menu/fonts/tajawal-700-latin.woff2', false);
    }

    public function test_english_restaurant_preloads_the_latin_font_subset(): void
    {
        Restaurant::factory()->create(['slug' => 'demo', 'name_en' => 'Demo', 'default_language' => 'en']);

        $res = $this->get('http://demo.xorder.io/menu');

        // The Arabic subset would never be used on this menu; preloading it
        // would cost a diner ~9 KB and leave the subset they need undiscovered
        // until the stylesheet parses.
        $res->assertSee('/menu/fonts/tajawal-400-latin.woff2', false);
        $res->assertSee('/menu/fonts/tajawal-700-latin.woff2', false);
        $res->assertDontSee('tajawal-400-arabic.woff2', false);
        $res->assertDontSee('tajawal-700-arabic.woff2', false);
        // Three preloads collapse to two: the shell's digits preload is the
        // same file the swapped 700 weight now points at, and asking the
        // browser to preload one file twice is the waste we are avoiding.
        $this->assertSame(2, substr_count($res->getContent(), 'rel="preload"'));
        $this->assertSame(1, substr_count($res->getContent(), 'tajawal-700-latin.woff2'));
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
        // Favicon is the PNG derivative, served from this menu's own origin;
        // the generic Xorder icons are removed.
        $res->assertSee('rel="icon" href="/storage/brand-cache/demo-icon.png"', false);
        $res->assertDontSee('favicon.svg', false);
        $res->assertDontSee('favicon-32.png', false);
        // No raw .webp survives in any icon/OG tag.
        $res->assertDontSee('/storage/covers/demo.webp', false);
        $res->assertDontSee('/storage/logos/demo.webp', false);

        Storage::disk('public')->assertExists('brand-cache/demo-og.jpg');
        Storage::disk('public')->assertExists('brand-cache/demo-icon.png');
    }

    public function test_order_tracking_links_are_not_indexable_but_the_menu_is(): void
    {
        Restaurant::factory()->create(['slug' => 'demo']);

        $tracking = $this->get('http://demo.xorder.io/menu/o/'.str_repeat('A', 40));
        $tracking->assertOk();
        $tracking->assertHeader('X-Robots-Tag', 'noindex, nofollow');

        $this->get('http://demo.xorder.io/menu')->assertHeaderMissing('X-Robots-Tag');
        $this->get('http://demo.xorder.io/menu/t/'.str_repeat('B', 10))->assertHeaderMissing('X-Robots-Tag');
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
            // Trailing slash is deliberate — it lands on the canonical path so the
            // guest doesn't eat nginx's /menu -> /menu/ redirect on top of this one.
            ->assertRedirect('https://demo.xorder.io/menu/');
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

    // ------------------------------------------------------- injection safety

    /**
     * Tenant text is attacker-controlled as far as the shell is concerned (a
     * restaurant admin types it). None of it may become markup.
     */
    public function test_tenant_text_cannot_inject_markup_into_the_shell(): void
    {
        Restaurant::factory()->create([
            'slug' => 'demo',
            'name_ar' => '"><img src=x onerror=alert(1)>',
            'name_en' => '<script>alert(1)</script>',
            'description_ar' => '"><svg onload=alert(2)>',
        ]);

        $html = $this->get('http://demo.xorder.io/menu')->assertOk()->getContent();

        // Everything outside the ld+json block must be entity-escaped: no raw
        // tag-opener from tenant input may survive there.
        $outsideLd = preg_replace('#<script type="application/ld\+json">.*?</script>#s', '', $html);

        $this->assertStringNotContainsString('<img src=x', $outsideLd);
        $this->assertStringNotContainsString('<svg onload', $outsideLd);
        $this->assertStringNotContainsString('<script>alert(1)</script>', $outsideLd);

        // The AR name is what leads (default_language is AR), and it reaches
        // the title and og:title entity-escaped rather than as markup.
        $this->assertStringContainsString(
            '<title>&quot;&gt;&lt;img src=x onerror=alert(1)&gt;</title>',
            $html
        );
        $this->assertStringContainsString(
            '<meta name="description" content="&quot;&gt;&lt;svg onload=alert(2)&gt;">',
            $html
        );
    }

    /**
     * The JSON-LD block is only safe because json_encode escapes `/`, turning a
     * `</script>` in tenant text into `<\/script>`. Adding JSON_UNESCAPED_SLASHES
     * — a tempting edit for prettier URLs — would break out of the script
     * element and hand the tenant stored XSS on every public menu.
     */
    public function test_tenant_text_cannot_break_out_of_the_json_ld_block(): void
    {
        Restaurant::factory()->create([
            'slug' => 'demo',
            'name_ar' => '</script><script>alert(1)</script>',
            'description_ar' => '</SCRIPT ><script>alert(2)</script>',
        ]);

        $html = $this->get('http://demo.xorder.io/menu')->assertOk()->getContent();

        preg_match('#<script type="application/ld\+json">(.*?)</script>#s', $html, $m);
        $this->assertNotEmpty($m, 'the ld+json block should be present');

        // Nothing inside the block may terminate it — that is the whole guard.
        $this->assertSame(0, preg_match_all('#</script#i', $m[1]));

        // …and it must still be valid JSON carrying the tenant text verbatim.
        $decoded = json_decode($m[1], true);
        $this->assertIsArray($decoded);
        $this->assertSame('</script><script>alert(1)</script>', $decoded['name']);
    }

    /**
     * e() escapes HTML but not `$`, and preg_replace expands `$0` inside a
     * replacement string — which used to splice the matched <title> element
     * into its own replacement.
     */
    public function test_a_dollar_backreference_in_the_name_is_not_expanded(): void
    {
        Restaurant::factory()->create([
            'slug' => 'demo',
            'name_ar' => '$0 $1 \\0 Cafe',
        ]);

        $html = $this->get('http://demo.xorder.io/menu')->assertOk()->getContent();

        $this->assertStringContainsString('<title>$0 $1 \\0 Cafe</title>', $html);
        $this->assertSame(1, substr_count($html, '<title>'));
    }
}
