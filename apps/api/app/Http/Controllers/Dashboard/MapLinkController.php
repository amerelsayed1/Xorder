<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ResolveMapLinkRequest;
use App\Services\MapLinkResolver;
use Illuminate\Http\JsonResponse;

class MapLinkController extends Controller
{
    public function __construct(private readonly MapLinkResolver $resolver) {}

    /**
     * Resolve a pasted Google Maps link (or raw "lat,lng") to coordinates so the
     * profile form can store latitude/longitude without the owner reading them
     * off the map by hand.
     */
    public function resolve(ResolveMapLinkRequest $request): JsonResponse
    {
        $coords = $this->resolver->resolve($request->validated('url'));

        if ($coords === null) {
            return response()->json([
                'message' => __('xorder.validation.map_link_unresolved'),
                'errors' => ['url' => [__('xorder.validation.map_link_unresolved')]],
            ], 422);
        }

        return response()->json(['data' => $coords]);
    }
}
