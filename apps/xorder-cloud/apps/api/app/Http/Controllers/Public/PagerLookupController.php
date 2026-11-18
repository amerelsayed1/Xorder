<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\PagerLookupService;
use App\Support\PublicImageUrl;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the join page's
 * two calls. No login: the restaurant is the one named in the URL (the page
 * takes it from its own host, as the menu does). The client types the number on
 * their slip; if it names one order of the last few hours, they get that
 * order's tracking token and the page moves to the order-number page.
 */
class PagerLookupController extends Controller
{
    public function __construct(private readonly PagerLookupService $lookup) {}

    /** GET: the restaurant's name, language and brand, so the page opens in the right language. */
    public function info(string $slug): JsonResponse
    {
        $restaurant = $this->restaurant($slug);

        return response()->json(['data' => ['restaurant' => $this->brand($restaurant)]])
            ->header('Cache-Control', 'no-store');
    }

    /** POST {number}: 200 found, 404 not found (yet), 409 more than one match. */
    public function lookup(Request $request, string $slug): JsonResponse
    {
        $restaurant = $this->restaurant($slug);

        $request->validate(['number' => ['required', 'string', 'max:40']], [
            'number.required' => __('xorder.messages.pager_number_invalid'),
        ]);

        ['status' => $status, 'order' => $order] = $this->lookup->find($restaurant, (string) $request->input('number'));

        $body = ['data' => ['state' => $status]];
        if ($order !== null) {
            $body['data']['tracking_token'] = $order->pickup_token;
        }

        $code = match ($status) {
            PagerLookupService::FOUND => 200,
            PagerLookupService::AMBIGUOUS => 409,
            default => 404,
        };

        return response()->json($body, $code)->header('Cache-Control', 'no-store');
    }

    private function restaurant(string $slug): Restaurant
    {
        $restaurant = Restaurant::query()->where('slug', Str::lower($slug))->first();
        abort_if($restaurant === null, 404, __('xorder.messages.order_not_found'));

        // Same gate as the tracking page: visible, and the feature is bought.
        if (! $restaurant->isPubliclyVisible() || ! $restaurant->hasFeature('guest_paging')) {
            abort(403, __('xorder.errors.feature_disabled'));
        }

        return $restaurant;
    }

    /** @return array<string, mixed> The same fields the order-number page reads. */
    private function brand(Restaurant $restaurant): array
    {
        return [
            'name' => $restaurant->name_en ?: $restaurant->name_ar,
            'name_ar' => $restaurant->name_ar ?: $restaurant->name_en,
            'name_en' => $restaurant->name_en ?: $restaurant->name_ar,
            'default_language' => $restaurant->default_language?->value ?? 'ar',
            'bilingual' => (bool) $restaurant->bilingual,
            'logo_url' => PublicImageUrl::relative($restaurant->logo_url),
            'brand_color' => $restaurant->brand_color,
        ];
    }
}
