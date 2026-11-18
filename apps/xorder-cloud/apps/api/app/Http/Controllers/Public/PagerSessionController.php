<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\PagerSession;
use App\Models\Restaurant;
use App\Services\PagerSessionService;
use App\Support\PublicImageUrl;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the join page's
 * two calls. No login: the restaurant is the one named in the URL (the page
 * takes it from its own host, as the menu does) and the phone proves its
 * session with the secret in the X-Pager-Secret header (never in a URL, so it
 * does not end up in access logs).
 */
class PagerSessionController extends Controller
{
    public function __construct(private readonly PagerSessionService $pager) {}

    /** POST: start a session, or resume the phone's own if it is still good. */
    public function start(Request $request, string $slug): JsonResponse
    {
        $restaurant = $this->restaurant($slug);

        try {
            ['session' => $session, 'secret' => $secret] = $this->pager->start($restaurant, $this->secret($request));
        } catch (RuntimeException) {
            abort(503, __('xorder.messages.pager_busy'));
        }

        return $this->respond($restaurant, $session, $secret, $secret !== null ? 201 : 200);
    }

    /** GET current: where the phone's session stands. 404 for anything it does not own. */
    public function show(Request $request, string $slug): JsonResponse
    {
        $restaurant = $this->restaurant($slug);

        $secret = $this->secret($request);
        $session = $secret !== null ? $this->pager->find($restaurant, $secret) : null;
        abort_if($session === null, 404, __('xorder.messages.order_not_found'));

        return $this->respond($restaurant, $session, null, 200);
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

    private function secret(Request $request): ?string
    {
        $secret = (string) $request->header('X-Pager-Secret', '');

        return preg_match('/^[A-Za-z0-9]{40}$/', $secret) === 1 ? $secret : null;
    }

    private function respond(Restaurant $restaurant, PagerSession $session, ?string $secret, int $status): JsonResponse
    {
        $state = $session->isBound() ? 'bound' : ($session->isExpired() ? 'expired' : 'open');

        $data = [
            'state' => $state,
            // Same fields the order-number page reads, so the join page opens in
            // the restaurant's language and brand before anything is paired.
            'restaurant' => [
                'name' => $restaurant->name_en ?: $restaurant->name_ar,
                'name_ar' => $restaurant->name_ar ?: $restaurant->name_en,
                'name_en' => $restaurant->name_en ?: $restaurant->name_ar,
                'default_language' => $restaurant->default_language?->value ?? 'ar',
                'bilingual' => (bool) $restaurant->bilingual,
                'logo_url' => PublicImageUrl::relative($restaurant->logo_url),
                'brand_color' => $restaurant->brand_color,
            ],
        ];

        if ($state === 'open') {
            $data['code'] = $session->code;
            $data['expires_at'] = $session->expires_at->toIso8601String();
        }

        if ($state === 'bound') {
            // The order's own tracking token: the phone goes to /menu/o/{token}.
            $data['tracking_token'] = $session->order?->pickup_token;
        }

        // Shown once, to the phone that just created the session.
        if ($secret !== null) {
            $data['secret'] = $secret;
        }

        return response()->json(['data' => $data], $status)
            ->header('Cache-Control', 'no-store');
    }
}
