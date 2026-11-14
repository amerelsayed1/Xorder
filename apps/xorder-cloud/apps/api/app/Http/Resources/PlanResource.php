<?php

namespace App\Http\Resources;

use App\Models\Plan;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Subscription plan for the Super Admin plans catalog.
 *
 * @mixin Plan
 */
class PlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'price' => $this->price !== null ? (float) $this->price : null,
            'currency' => $this->currency->value,
            'currency_symbol' => $this->currency->symbol(),
            'feature_keys' => $this->feature_keys ?? [],
            'max_items' => $this->max_items,
            'max_categories' => $this->max_categories,
            'max_branches' => $this->max_branches,
            'max_staff' => $this->max_staff,
            'max_terminals' => $this->max_terminals,
            'is_active' => $this->is_active,
            'is_recommended' => $this->is_recommended,
            'sort_order' => $this->sort_order,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
