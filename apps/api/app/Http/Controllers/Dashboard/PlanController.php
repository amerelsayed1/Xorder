<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\RoleEnum;
use App\Http\Controllers\Controller;
use App\Models\Branch;
use App\Models\Category;
use App\Models\LandingContent;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\PosProvisioningService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * "My plan": what the restaurant is on, how much of it is used, and what the
 * other plans offer. Read-only — upgrading is a conversation with Xorder (the
 * support WhatsApp), not a checkout, until a payment gateway exists.
 *
 * Every limit shown here is one the platform actually enforces
 * (PlanLimitService, and PosProvisioningService for till seats), counted the
 * same way, so a meter can never say "room left" while a create is refused.
 */
class PlanController extends Controller
{
    public function __construct(private readonly PosProvisioningService $pos) {}

    public function show(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant->loadMissing('features');
        $plan = $restaurant->subscription_plan
            ? Plan::where('name', $restaurant->subscription_plan)->first()
            : null;

        return response()->json([
            'data' => [
                'plan' => $plan ? $this->planCard($plan) : null,
                // The name stays visible even when no catalogue plan matches it
                // (a bespoke deal typed by the Super Admin), so the page can say
                // what the restaurant is on rather than "no plan".
                'plan_name' => $restaurant->subscription_plan,
                'subscription' => $this->subscription($restaurant),
                'usage' => $this->usage($restaurant, $plan),
                'features' => $restaurant->features->where('is_enabled', true)->pluck('feature_key')->values(),
                'plans' => Plan::query()->where('is_active', true)
                    ->orderBy('sort_order')->orderBy('id')->get()
                    ->map(fn (Plan $p) => $this->planCard($p) + ['current' => $plan?->id === $p->id])
                    ->values(),
                'support_whatsapp' => $this->supportWhatsapp(),
            ],
        ]);
    }

    /** @return array<string, mixed> */
    private function planCard(Plan $plan): array
    {
        return [
            'id' => $plan->id,
            'name' => $plan->name,
            // null => custom pricing; 0 => free; otherwise the monthly amount.
            'price' => $plan->price !== null ? (float) $plan->price : null,
            'currency' => $plan->currency?->value,
            'recommended' => (bool) $plan->is_recommended,
            'feature_keys' => $plan->feature_keys ?? [],
            // null = unlimited.
            'limits' => [
                'items' => $plan->max_items,
                'categories' => $plan->max_categories,
                'branches' => $plan->max_branches,
                'staff' => $plan->max_staff,
                'terminals' => $plan->max_terminals,
            ],
        ];
    }

    /** @return array<string, mixed> */
    private function subscription(Restaurant $restaurant): array
    {
        $end = $restaurant->subscription_end_date;
        $today = Carbon::parse($restaurant->today());

        return [
            'status' => $restaurant->subscription_status?->value,
            'start_date' => $restaurant->subscription_start_date?->toDateString(),
            'end_date' => $end?->toDateString(),
            // Whole days left on the restaurant's own calendar; negative once
            // past, null when the subscription has no end date.
            'days_left' => $end ? (int) $today->diffInDays($end->copy()->startOfDay(), false) : null,
        ];
    }

    /**
     * Each meter is counted exactly as its enforcement counts it. Till seats
     * appear only for restaurants that run the POS.
     *
     * @return list<array{key: string, used: int, max: int|null}>
     */
    private function usage(Restaurant $restaurant, ?Plan $plan): array
    {
        // Tenant-scoped by the global RestaurantScope.
        $meters = [
            ['key' => 'items', 'used' => MenuItem::count(), 'max' => $plan?->max_items],
            ['key' => 'categories', 'used' => Category::count(), 'max' => $plan?->max_categories],
            ['key' => 'branches', 'used' => Branch::count(), 'max' => $plan?->max_branches],
            // User has no RestaurantScope: scoped by hand, as PlanLimitService does.
            ['key' => 'staff', 'used' => User::where('restaurant_id', $restaurant->id)
                ->where('role', RoleEnum::RESTAURANT_STAFF)->count(), 'max' => $plan?->max_staff],
        ];

        if ($restaurant->hasFeature('pos')) {
            // Licence seats override the plan's, exactly as provisioning decides.
            $seats = $this->pos->seatUsage($restaurant);
            $meters[] = ['key' => 'terminals', 'used' => $seats['occupied'], 'max' => $seats['max']];
        }

        return $meters;
    }

    /** Xorder's own WhatsApp from the landing CMS, digits only; null if unset. */
    private function supportWhatsapp(): ?string
    {
        $number = preg_replace('/\D/', '', (string) (LandingContent::current()->content['whatsapp']['number'] ?? ''));

        return $number !== '' ? $number : null;
    }
}
