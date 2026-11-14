<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreCustomerRequest;
use App\Services\CustomerDirectory;
use App\Services\PublicMenuService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;

/**
 * Saves a guest's contact details to the restaurant's customer directory at
 * WhatsApp checkout. WhatsApp orders leave no system record, but the diner is
 * still captured so the restaurant keeps its customer list across every
 * ordering type. No order is created here.
 */
class PublicCustomerController extends Controller
{
    public function __construct(
        private readonly PublicMenuService $menu,
        private readonly CustomerDirectory $directory,
    ) {}

    public function store(StoreCustomerRequest $request, string $slug): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null || ! $this->menu->isVisible($restaurant)) {
            return response()->json(['message' => __('xorder.messages.restaurant_not_found')], 404);
        }

        // Only capture where the menu actually takes orders at all.
        if ($restaurant->effectiveOrderingMode() === null) {
            return response()->json(['message' => __('xorder.messages.ordering_disabled')], 422);
        }

        // Pin the tenant so the directory upsert is scoped/stamped to this
        // restaurant (public request has no auth context). Released in finally.
        TenantContext::overrideId($restaurant->id);

        try {
            $this->directory->upsert($request->validated());
        } finally {
            TenantContext::clearOverride();
        }

        return response()->json(['saved' => true], 201);
    }
}
