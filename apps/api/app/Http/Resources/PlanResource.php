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
            'features' => $this->features ?? [],
            'max_items' => $this->max_items,
            'max_branches' => $this->max_branches,
            'is_active' => $this->is_active,
            'sort_order' => $this->sort_order,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
