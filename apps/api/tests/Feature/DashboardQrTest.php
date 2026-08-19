<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The restaurant's own menu QR code — the thing customers physically scan, and
 * so the one artefact of this product that gets printed and stuck on a wall.
 * A QR that encodes the wrong restaurant is unrecoverable once printed.
 */
class DashboardQrTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'bistro',
        ]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    public function test_it_returns_an_svg_and_the_public_url_it_encodes(): void
    {
        $res = $this->actingAs($this->admin)->getJson('/api/dashboard/qr')->assertOk();

        $this->assertStringContainsString('<svg', $res->json('data.svg'));
        $this->assertSame($this->restaurant->publicUrl(), $res->json('data.public_url'));
        $this->assertStringContainsString('bistro', $res->json('data.public_url'));
    }

    public function test_the_qr_encodes_this_restaurant_and_not_another(): void
    {
        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'rival']);
        $theirAdmin = User::factory()->restaurantAdmin($other->id)->create();

        $mine = $this->actingAs($this->admin)->getJson('/api/dashboard/qr')->json('data.public_url');
        $theirs = $this->actingAs($theirAdmin)->getJson('/api/dashboard/qr')->json('data.public_url');

        $this->assertStringContainsString('bistro', $mine);
        $this->assertStringContainsString('rival', $theirs);
        $this->assertNotSame($mine, $theirs);
    }

    public function test_the_download_is_a_png_attachment(): void
    {
        $res = $this->actingAs($this->admin)->get('/api/dashboard/qr/download')->assertOk();

        $res->assertHeader('Content-Type', 'image/png');
        $this->assertStringContainsString('attachment;', $res->headers->get('Content-Disposition'));
        // PNG magic number — proves an image came back, not an error page.
        $this->assertStringStartsWith("\x89PNG", $this->streamed($res));
    }

    public function test_the_qr_endpoints_require_authentication(): void
    {
        $this->getJson('/api/dashboard/qr')->assertUnauthorized();
        $this->getJson('/api/dashboard/qr/download')->assertUnauthorized();
    }

    private function streamed($res): string
    {
        ob_start();
        $res->baseResponse->sendContent();

        return ob_get_clean();
    }
}
