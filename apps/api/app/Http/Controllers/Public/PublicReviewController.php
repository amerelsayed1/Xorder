<?php

namespace App\Http\Controllers\Public;

use App\Enums\ReviewStatus;
use App\Http\Controllers\Controller;
use App\Models\InternalReview;
use App\Models\MenuSession;
use App\Models\Order;
use App\Rules\MobileNumber;
use App\Services\NotificationService;
use App\Services\PublicMenuService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Customer-facing private feedback. A diner leaves a rating (and optional
 * comment/contact details) that goes only to the restaurant — never published.
 */
class PublicReviewController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu) {}

    /** POST /public/restaurants/{slug}/reviews */
    public function store(Request $request, string $slug, NotificationService $notifications): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null
            || ! $restaurant->isPubliclyVisible()
            || ! $restaurant->hasFeature('internal_reviews')) {
            abort(403, __('xorder.errors.feature_disabled'));
        }

        $data = $request->validate([
            'rating' => ['required', 'integer', 'between:1,5'],
            'comment' => ['nullable', 'string', 'max:2000'],
            'customer_name' => ['nullable', 'string', 'max:150'],
            'customer_phone' => ['nullable', 'string', 'max:32', new MobileNumber],
            'contact_permission' => ['nullable', 'boolean'],
            'session_token' => ['nullable', 'string'],
            'order_id' => ['nullable', 'integer'],
        ]);

        $review = new InternalReview([
            'rating' => $data['rating'],
            'comment' => $data['comment'] ?? null,
            'customer_name' => $data['customer_name'] ?? null,
            'customer_phone' => $data['customer_phone'] ?? null,
            'contact_permission' => (bool) ($data['contact_permission'] ?? false),
            'status' => ReviewStatus::NEW->value,
        ]);
        $review->restaurant_id = $restaurant->id;

        // A table QR session links the review to its physical table/area/branch.
        if (! empty($data['session_token'])) {
            $session = MenuSession::withoutGlobalScopes()
                ->where('restaurant_id', $restaurant->id)
                ->where('session_token', $data['session_token'])
                ->first();

            if ($session !== null) {
                // One review per table session — surface the existing one rather
                // than creating a duplicate (FR-REVIEW-017).
                $existing = InternalReview::withoutGlobalScopes()
                    ->where('menu_session_id', $session->id)
                    ->first();

                if ($existing !== null) {
                    return response()->json([
                        'data' => $this->payload($restaurant),
                        'duplicate' => true,
                        'message' => __('xorder.messages.review_created'),
                    ], 200);
                }

                $review->branch_id = $session->branch_id;
                $review->dining_area_id = $session->dining_area_id;
                $review->table_id = $session->table_id;
                $review->menu_session_id = $session->id;
            }
        }

        // Link to an order when it belongs to this restaurant.
        if (! empty($data['order_id'])) {
            $order = Order::withoutGlobalScopes()
                ->where('restaurant_id', $restaurant->id)
                ->where('id', $data['order_id'])
                ->first();

            if ($order !== null) {
                $review->order_id = $order->id;
            }
        }

        $review->save();

        // Notify the restaurant of the new feedback — after the response is
        // flushed so the FCM round-trip never delays the diner. Low ratings are
        // exactly what an owner wants to catch fast.
        $restaurantId = $restaurant->id;
        $lang = $restaurant->default_language->value;
        $rating = (int) $review->rating;
        $reviewId = $review->id;
        app()->terminating(function () use ($notifications, $restaurantId, $lang, $rating, $reviewId) {
            $notifications->toRestaurant(
                $restaurantId,
                'review.created',
                __('xorder.messages.push_new_review_title', [], $lang),
                __('xorder.messages.push_new_review_body', ['stars' => str_repeat('★', $rating), 'rating' => $rating], $lang),
                ['review_id' => (string) $reviewId, 'rating' => (string) $rating],
                '/admin/reviews',
            );
        });

        return response()->json([
            'data' => $this->payload($restaurant),
            'message' => __('xorder.messages.review_created'),
        ], 201);
    }

    /** @return array<string,mixed> */
    private function payload($restaurant): array
    {
        $locale = app()->getLocale();
        $thankYou = $locale === 'ar'
            ? ($restaurant->review_thank_you_ar ?: $restaurant->review_thank_you_en)
            : ($restaurant->review_thank_you_en ?: $restaurant->review_thank_you_ar);

        return [
            'thank_you' => $thankYou ?: __('xorder.messages.review_thanks'),
            'public_review_url' => $restaurant->review_public_url,
        ];
    }
}
