<?php

namespace App\Services;

use App\Models\Restaurant;
use Illuminate\Support\Str;

class SlugService
{
    /**
     * Normalize an arbitrary string into a valid slug:
     * lowercase, [a-z0-9-], no spaces/specials, collapsed hyphens.
     */
    public function normalize(string $value): string
    {
        return Str::slug($value);
    }

    public function isAvailable(string $slug, ?int $ignoreId = null): bool
    {
        return ! Restaurant::query()
            ->where('slug', $slug)
            ->when($ignoreId, fn ($q) => $q->whereKeyNot($ignoreId))
            ->exists();
    }

    /**
     * Return a unique slug derived from $base, appending -2, -3, ... on
     * collision. $ignoreId excludes the restaurant being updated.
     */
    public function unique(string $base, ?int $ignoreId = null): string
    {
        $slug = $this->normalize($base);
        $candidate = $slug;
        $suffix = 2;

        while (! $this->isAvailable($candidate, $ignoreId)) {
            $candidate = "{$slug}-{$suffix}";
            $suffix++;
        }

        return $candidate;
    }
}
