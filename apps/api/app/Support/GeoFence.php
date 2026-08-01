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
     * @param  mixed  $fence
     */
    public static function contains(float $lat, float $lng, $fence): bool
    {
        if (! is_array($fence)) {
            return false;
        }

        return match (self::type($fence)) {
            'radius' => self::withinRadius($lat, $lng, $fence),
            'polygon' => self::pointInPolygon($lat, $lng, self::points($fence)),
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

    private static function withinRadius(float $lat, float $lng, array $fence): bool
    {
        $center = $fence['center'] ?? null;
        $radius = (float) ($fence['radius'] ?? 0);
        if (! is_array($center) || $radius <= 0) {
            return false;
        }

        return self::haversineMetres($lat, $lng, (float) $center['lat'], (float) $center['lng']) <= $radius;
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
