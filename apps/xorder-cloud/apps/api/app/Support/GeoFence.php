<?php

namespace App\Support;

/**
 * Geofence geometry helpers. A fence is a self-describing array:
 *   ['type' => 'polygon', 'points' => [['lat'=>..,'lng'=>..], ...]]
 *   ['type' => 'radius',  'center' => ['lat'=>..,'lng'=>..], 'radius' => <metres>]
 * Coordinates are (lat, lng) degrees.
 */
class GeoFence
{
    private const EARTH_RADIUS_M = 6371000;

    /**
     * Is the point inside the fence? Returns false for an unset or malformed
     * fence so a half-configured fence never traps anyone.
     *
     * $toleranceMetres widens the fence outward by that many metres to absorb
     * GPS uncertainty — a diner whose fix is fuzzy but who could plausibly be
     * inside is admitted rather than falsely rejected. Pass the device's
     * reported accuracy (capped by the caller).
     *
     * @param  mixed  $fence
     */
    public static function contains(float $lat, float $lng, $fence, float $toleranceMetres = 0.0): bool
    {
        if (! is_array($fence)) {
            return false;
        }

        $tolerance = max(0.0, $toleranceMetres);

        return match (self::type($fence)) {
            'radius' => self::withinRadius($lat, $lng, $fence, $tolerance),
            'polygon' => self::withinPolygon($lat, $lng, self::points($fence), $tolerance),
            default => false,
        };
    }

    /** True when a fence is well-formed enough to enforce. */
    public static function isEnforceable($fence): bool
    {
        if (! is_array($fence)) {
            return false;
        }

        return match (self::type($fence)) {
            'radius' => isset($fence['center']['lat'], $fence['center']['lng'])
                && (float) ($fence['radius'] ?? 0) > 0,
            'polygon' => count(self::points($fence)) >= 3,
            default => false,
        };
    }

    /**
     * A single "how tight is this fence" scale in metres, used to derive how
     * precise a GPS fix must be before it can reliably resolve inside/outside.
     * For a radius fence it's the radius; for a polygon it's the inradius
     * (centroid to nearest edge — the fence's narrowest half-width). Returns
     * null for a fence that isn't enforceable.
     *
     * @param  mixed  $fence
     */
    public static function characteristicRadiusMetres($fence): ?float
    {
        if (! is_array($fence)) {
            return null;
        }

        return match (self::type($fence)) {
            'radius' => ($r = (float) ($fence['radius'] ?? 0)) > 0 ? $r : null,
            'polygon' => self::polygonInradiusMetres(self::points($fence)),
            default => null,
        };
    }

    /**
     * Distance from the polygon's centroid to its nearest edge, in metres — a
     * stable proxy for the fence's half-width. Null for a degenerate polygon.
     *
     * @param  array<int, array{lat: float|int|string, lng: float|int|string}>  $polygon
     */
    private static function polygonInradiusMetres(array $polygon): ?float
    {
        $n = count($polygon);
        if ($n < 3) {
            return null;
        }

        $lat = 0.0;
        $lng = 0.0;
        foreach ($polygon as $p) {
            $lat += (float) $p['lat'];
            $lng += (float) $p['lng'];
        }

        $d = self::distanceToPolygonMetres($lat / $n, $lng / $n, $polygon);

        return is_finite($d) ? $d : null;
    }

    /** Resolve the shape, tolerating a legacy bare list of vertices as polygon. */
    private static function type(array $fence): string
    {
        if (isset($fence['type'])) {
            return (string) $fence['type'];
        }

        return array_key_exists(0, $fence) ? 'polygon' : 'unknown';
    }

    /** The vertex list, whether nested under `points` or a legacy bare array. */
    private static function points(array $fence): array
    {
        $points = $fence['points'] ?? $fence;

        return is_array($points) ? array_values($points) : [];
    }

    private static function withinRadius(float $lat, float $lng, array $fence, float $tolerance = 0.0): bool
    {
        $center = $fence['center'] ?? null;
        $radius = (float) ($fence['radius'] ?? 0);
        if (! is_array($center) || $radius <= 0) {
            return false;
        }

        return self::haversineMetres($lat, $lng, (float) $center['lat'], (float) $center['lng']) <= $radius + $tolerance;
    }

    /**
     * Inside the polygon, or within $tolerance metres of its boundary. The
     * tolerance test measures the shortest distance from the point to any edge,
     * so GPS jitter near a wall doesn't lock out a diner who is really inside.
     *
     * @param  array<int, array{lat: float|int|string, lng: float|int|string}>  $polygon
     */
    private static function withinPolygon(float $lat, float $lng, array $polygon, float $tolerance = 0.0): bool
    {
        if (self::pointInPolygon($lat, $lng, $polygon)) {
            return true;
        }

        return $tolerance > 0 && self::distanceToPolygonMetres($lat, $lng, $polygon) <= $tolerance;
    }

    /**
     * Shortest distance in metres from a point to the polygon's boundary. Uses a
     * local equirectangular projection (metres east/north of the point), exact
     * enough over a branch-sized area.
     *
     * @param  array<int, array{lat: float|int|string, lng: float|int|string}>  $polygon
     */
    public static function distanceToPolygonMetres(float $lat, float $lng, array $polygon): float
    {
        $n = count($polygon);
        if ($n < 2) {
            return INF;
        }

        $mPerDegLat = deg2rad(1) * self::EARTH_RADIUS_M;
        $mPerDegLng = $mPerDegLat * cos(deg2rad($lat));

        // Point at the origin; project each vertex to local metres.
        $project = static fn (array $p): array => [
            ((float) $p['lng'] - $lng) * $mPerDegLng, // x, east
            ((float) $p['lat'] - $lat) * $mPerDegLat, // y, north
        ];

        $min = INF;
        for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
            [$ax, $ay] = $project($polygon[$j]);
            [$bx, $by] = $project($polygon[$i]);
            $min = min($min, self::pointToSegmentMetres($ax, $ay, $bx, $by));
        }

        return $min;
    }

    /** Distance from the origin (0,0) to the segment A→B, all in metres. */
    private static function pointToSegmentMetres(float $ax, float $ay, float $bx, float $by): float
    {
        $dx = $bx - $ax;
        $dy = $by - $ay;
        $lenSq = $dx * $dx + $dy * $dy;
        if ($lenSq <= 0.0) {
            return sqrt($ax * $ax + $ay * $ay);
        }

        // Projection factor of the origin onto the segment, clamped to [0,1].
        $tRaw = -($ax * $dx + $ay * $dy) / $lenSq;
        $t = max(0.0, min(1.0, $tRaw));
        $cx = $ax + $t * $dx;
        $cy = $ay + $t * $dy;

        return sqrt($cx * $cx + $cy * $cy);
    }

    /**
     * Ray-casting point-in-polygon test. Latitude is the vertical axis (y),
     * longitude the horizontal (x). A branch premises is small enough that a
     * flat-plane test is exact here.
     *
     * @param  array<int, array{lat: float|int|string, lng: float|int|string}>  $polygon
     */
    public static function pointInPolygon(float $lat, float $lng, array $polygon): bool
    {
        $n = count($polygon);
        if ($n < 3) {
            return false;
        }

        $inside = false;
        for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
            $yi = (float) $polygon[$i]['lat'];
            $xi = (float) $polygon[$i]['lng'];
            $yj = (float) $polygon[$j]['lat'];
            $xj = (float) $polygon[$j]['lng'];

            $straddles = ($yi > $lat) !== ($yj > $lat);
            if ($straddles) {
                $denom = ($yj - $yi) ?: 1e-12;
                $xCross = ($xj - $xi) * ($lat - $yi) / $denom + $xi;
                if ($lng < $xCross) {
                    $inside = ! $inside;
                }
            }
        }

        return $inside;
    }

    /** Great-circle distance between two points, in metres. */
    public static function haversineMetres(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return 2 * self::EARTH_RADIUS_M * asin(min(1.0, sqrt($a)));
    }
}
