<?php

namespace Tests\Unit;

use App\Support\GeoFence;
use PHPUnit\Framework\TestCase;

class GeoFenceTest extends TestCase
{
    /** A polygon fence: unit square from (0,0) to (10,10) in (lat,lng). */
    private array $polygon = [
        'type' => 'polygon',
        'points' => [
            ['lat' => 0, 'lng' => 0],
            ['lat' => 0, 'lng' => 10],
            ['lat' => 10, 'lng' => 10],
            ['lat' => 10, 'lng' => 0],
        ],
    ];

    // ── Polygon ────────────────────────────────────────────────────────────

    public function test_polygon_contains_inside_point(): void
    {
        $this->assertTrue(GeoFence::contains(5, 5, $this->polygon));
    }

    public function test_polygon_excludes_outside_point(): void
    {
        $this->assertFalse(GeoFence::contains(20, 20, $this->polygon));
        $this->assertFalse(GeoFence::contains(5, -1, $this->polygon));
    }

    public function test_polygon_with_string_coords_is_coerced(): void
    {
        $poly = ['type' => 'polygon', 'points' => [
            ['lat' => '0', 'lng' => '0'], ['lat' => '0', 'lng' => '10'],
            ['lat' => '10', 'lng' => '10'], ['lat' => '10', 'lng' => '0'],
        ]];
        $this->assertTrue(GeoFence::contains(5, 5, $poly));
    }

    public function test_legacy_bare_array_is_treated_as_polygon(): void
    {
        $legacy = [['lat' => 0, 'lng' => 0], ['lat' => 0, 'lng' => 10], ['lat' => 10, 'lng' => 5]];
        $this->assertTrue(GeoFence::isEnforceable($legacy));
        $this->assertTrue(GeoFence::contains(3, 5, $legacy));
    }

    // ── Radius ─────────────────────────────────────────────────────────────

    public function test_radius_contains_point_within_distance(): void
    {
        // ~150 m radius around a Cairo point; a point ~55 m away is inside.
        $fence = ['type' => 'radius', 'center' => ['lat' => 30.0444, 'lng' => 31.2357], 'radius' => 150];
        $this->assertTrue(GeoFence::contains(30.0448, 31.2360, $fence));
    }

    public function test_radius_excludes_point_beyond_distance(): void
    {
        $fence = ['type' => 'radius', 'center' => ['lat' => 30.0444, 'lng' => 31.2357], 'radius' => 150];
        $this->assertFalse(GeoFence::contains(30.10, 31.30, $fence)); // several km away
    }

    public function test_radius_needs_center_and_positive_radius(): void
    {
        $this->assertFalse(GeoFence::isEnforceable(['type' => 'radius', 'radius' => 100]));
        $this->assertFalse(GeoFence::isEnforceable(['type' => 'radius', 'center' => ['lat' => 30, 'lng' => 31], 'radius' => 0]));
        $this->assertTrue(GeoFence::isEnforceable(['type' => 'radius', 'center' => ['lat' => 30, 'lng' => 31], 'radius' => 50]));
    }

    // ── Guards ─────────────────────────────────────────────────────────────

    public function test_degenerate_or_missing_fence_contains_nobody(): void
    {
        $this->assertFalse(GeoFence::contains(5, 5, null));
        $this->assertFalse(GeoFence::contains(5, 5, []));
        $this->assertFalse(GeoFence::contains(5, 5, ['type' => 'polygon', 'points' => [['lat' => 0, 'lng' => 0]]]));
        $this->assertFalse(GeoFence::isEnforceable(null));
        $this->assertFalse(GeoFence::isEnforceable(['type' => 'polygon', 'points' => [['lat' => 0, 'lng' => 0]]]));
    }

    public function test_haversine_matches_known_distance(): void
    {
        // ~111 km per degree of latitude near the equator.
        $m = GeoFence::haversineMetres(0, 0, 1, 0);
        $this->assertEqualsWithDelta(111195, $m, 500);
    }
}
