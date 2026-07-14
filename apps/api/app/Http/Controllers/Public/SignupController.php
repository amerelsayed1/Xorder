<?php

namespace App\Http\Controllers\Public;

use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\SignupRequest;
use App\Services\RestaurantProvisioningService;
use App\Services\SlugService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;

/**
 * Self-serve restaurant signup. OFF by default (SELF_SERVE_SIGNUP env) —
 * the platform launches sales-led via the leads inbox; flip the flag when
 * the funnel is ready for automatic provisioning.
 */
class SignupController extends Controller
{
    public function __construct(
        private readonly RestaurantProvisioningService $provisioning,
        private readonly SlugService $slugs,
    ) {}

    public function store(SignupRequest $request): JsonResponse
    {
        abort_unless((bool) config('platform.self_serve_signup'), 404);

        // Same honeypot pattern as the leads form: bots get a believable
        // success and provision nothing.
        if ($request->filled('website')) {
            return response()->json(['message' => __('xorder.messages.signup_received')], 201);
        }

        $data = $request->validated();

        // Arabic-only names slugify to '' — fall back to a random handle the
        // owner can change later; reserved slugs get pushed to a suffix by
        // uniqueness against the (seeded) reserved list check below.
        $base = $this->slugs->normalize($data['restaurant_name']);
        if ($base === '' || in_array($base, config('platform.reserved_slugs'), true)) {
            $base = 'r-'.Str::lower(Str::random(6));
        }

        $trialDays = (int) config('platform.signup_trial_days', 14);

        $result = $this->provisioning->provision([
            'name_en' => $data['restaurant_name'],
            'name_ar' => $data['restaurant_name_ar'] ?? $data['restaurant_name'],
            'slug' => $base,
            'whatsapp_number' => $data['whatsapp'] ?? null,
            'status' => RestaurantStatus::ACTIVE,
            'subscription_status' => SubscriptionStatus::TRIAL,
            'subscription_start_date' => now()->toDateString(),
            'subscription_end_date' => now()->addDays($trialDays)->toDateString(),
        ], [
            'name' => $data['name'],
            'email' => $data['email'],
        ]);

        return response()->json([
            'data' => [
                'public_url' => $result['restaurant']->publicUrl(),
                'login_url' => rtrim(config('app.url'), '/').'/login',
                'trial_days' => $trialDays,
            ],
            'message' => __('xorder.messages.signup_received'),
        ], 201);
    }
}
