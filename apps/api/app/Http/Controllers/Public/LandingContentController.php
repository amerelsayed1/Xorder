<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\LandingContent;
use App\Models\Plan;
use Illuminate\Http\JsonResponse;

class LandingContentController extends Controller
{
    /**
     * Public landing page content consumed by the standalone landing app.
     *
     * The pricing cards are generated live from the Plans catalog (managed by
     * the Super Admin under /plans) so the marketing site always reflects the
     * real, current plans. Only the section copy (heading, sub, badge/CTA
     * labels) stays editable landing content.
     */
    public function show(): JsonResponse
    {
        $content = LandingContent::current()->content;
        $content['pricing'] = $this->pricingFromPlans($content['pricing'] ?? []);

        return response()->json(['data' => $content]);
    }

    /**
     * Merge the editable pricing section copy with cards derived from active
     * plans. Each card carries structured price data (amount + currency code,
     * or null for custom pricing) and the plan's entitlement keys — the landing
     * app localizes the amount and maps each key to its feature label.
     *
     * @param  array<string,mixed>  $pricing
     * @return array<string,mixed>
     */
    private function pricingFromPlans(array $pricing): array
    {
        $pricing['plans'] = Plan::query()
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get()
            ->map(fn (Plan $plan) => [
                'name' => $plan->name,
                'recommended' => (bool) $plan->is_recommended,
                'enabled' => true,
                // null => custom pricing; 0 => free; otherwise the monthly amount.
                'price' => $plan->price !== null ? (float) $plan->price : null,
                'currency' => $plan->currency->value,
                'feature_keys' => $plan->feature_keys ?? [],
                // Branch allowance for the marketing card: null = unlimited (only
                // meaningful when the plan also grants multi_branch).
                'max_branches' => $plan->max_branches,
            ])
            ->all();

        // Plans carry a single price, so the monthly/yearly toggle no longer
        // applies — drop it if it lingers in stored content.
        unset($pricing['billing']);

        return $pricing;
    }
}
