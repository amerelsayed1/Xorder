<?php

namespace App\Http\Resources;

use App\Models\OptionGroup;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin OptionGroup */
class OptionGroupResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name_en' => $this->name_en,
            'name_ar' => $this->name_ar,
            // Diner-facing heading; blank means "use the library name".
            'display_name_en' => $this->display_name_en,
            'display_name_ar' => $this->display_name_ar,
            'is_required' => $this->is_required,
            'is_variant' => $this->is_variant,
            'max_select' => $this->max_select,
            // How broadly the group applies: 'items' (per-item) | 'categories' | 'all'.
            'apply_scope' => $this->apply_scope,
            'category_ids' => $this->whenLoaded('categories', fn () => $this->categories->pluck('id')->values()),
            'categories' => $this->whenLoaded('categories', fn () => $this->categories->map(fn ($c) => [
                'id' => $c->id,
                'name_en' => $c->name_en,
                'name_ar' => $c->name_ar,
            ])->values()),
            // How many items currently use this shared group (present when counted).
            'items_count' => $this->whenCounted('menuItems'),
            'options' => $this->whenLoaded('options', fn () => $this->options->map(fn ($o) => [
                'id' => $o->id,
                'name_en' => $o->name_en,
                'name_ar' => $o->name_ar,
                'price' => $o->price,
                'discounted_price' => $o->discounted_price,
                'is_available' => $o->is_available,
            ])->values()),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
