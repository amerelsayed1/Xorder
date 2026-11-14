<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use App\Services\MapLinkResolver;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The profile form lets owners paste a Google Maps link instead of typing raw
 * latitude/longitude. MapLinkResolver turns that link (or a share short link,
 * or a bare "lat,lng") into coordinates.
 */
class MapLinkResolverTest extends TestCase
{
    use RefreshDatabase;

    private function resolver(): MapLinkResolver
    {
        return app(MapLinkResolver::class);
    }

    public function test_parses_at_style_map_url_without_network(): void
    {
        Http::preventStrayRequests(); // no outbound call for inline coordinates
        $coords = $this->resolver()->resolve('https://www.google.com/maps/@31.0347174,31.3642686,15z');
        $this->assertEqualsWithDelta(31.0347174, $coords['latitude'], 1e-6);
        $this->assertEqualsWithDelta(31.3642686, $coords['longitude'], 1e-6);
    }

    public function test_parses_place_pin_data_param(): void
    {
        Http::preventStrayRequests();
        $url = 'https://www.google.com/maps/place/Cafe/@30.05,31.23,17z/data=!3d30.0444196!4d31.2357116';
        $coords = $this->resolver()->resolve($url);
        // The !3d/!4d pin wins over the @ viewport centre.
        $this->assertEqualsWithDelta(30.0444196, $coords['latitude'], 1e-6);
        $this->assertEqualsWithDelta(31.2357116, $coords['longitude'], 1e-6);
    }

    public function test_parses_query_param_and_raw_pair(): void
    {
        Http::preventStrayRequests();
        $this->assertEqualsWithDelta(
            30.0444, $this->resolver()->resolve('https://maps.google.com/?q=30.0444,31.2357')['latitude'], 1e-6
        );
        $this->assertEqualsWithDelta(
            31.2357, $this->resolver()->resolve('30.0444, 31.2357')['longitude'], 1e-6
        );
    }

    public function test_follows_short_link_redirect_to_find_coordinates(): void
    {
        Http::fake([
            'maps.app.goo.gl/*' => Http::response('', 302, [
                'Location' => 'https://www.google.com/maps/place/X/@29.9773,31.1325,17z/data=!3d29.9772962!4d31.1324955',
            ]),
        ]);

        $coords = $this->resolver()->resolve('https://maps.app.goo.gl/abc123');
        $this->assertEqualsWithDelta(29.9772962, $coords['latitude'], 1e-6);
        $this->assertEqualsWithDelta(31.1324955, $coords['longitude'], 1e-6);
    }

    public function test_rejects_link_with_no_coordinates(): void
    {
        Http::fake(['*' => Http::response('no coords here', 200)]);
        $this->assertNull($this->resolver()->resolve('https://www.google.com/maps/place/Just+A+Name'));
    }

    public function test_does_not_fetch_non_google_hosts_ssrf_guard(): void
    {
        Http::fake(); // any outbound request would be recorded
        $this->assertNull($this->resolver()->resolve('https://evil.example.com/maps'));
        Http::assertNothingSent();
    }

    public function test_endpoint_resolves_link_for_restaurant_admin(): void
    {
        Http::preventStrayRequests();
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/geo/resolve-map-link', [
                'url' => 'https://www.google.com/maps/@31.0347174,31.3642686,15z',
            ])
            ->assertOk()
            ->assertJsonPath('data.latitude', 31.0347174)
            ->assertJsonPath('data.longitude', 31.3642686);
    }

    public function test_endpoint_returns_422_when_unresolvable(): void
    {
        Http::fake(['*' => Http::response('nope', 200)]);
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)
            ->postJson('/api/dashboard/geo/resolve-map-link', [
                'url' => 'https://www.google.com/maps/place/Nameless',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('url');
    }
}
