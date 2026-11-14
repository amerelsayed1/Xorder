<?php

namespace App\Http\Resources;

use App\Models\MenuItem;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin MenuItem */
class MenuItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Same derivation the public menu uses: a size group prices the item,
        // so the form and list show the default size rather than a column the
        // diner never pays. Unloaded relations derive nothing and fall back.
        [$price, $discountedPrice] = $this->resource->displayPricing();

        return [
            'id' => $this->id,
            'restaurant_id' => $this->restaurant_id,
            'category_id' => $this->category_id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'price' => $price,
            'discounted_price' => $discountedPrice,
            'image_url' => $this->image_url,
            'is_available' => $this->is_available,
            'is_featured' => $this->is_featured,
            'display_order' => $this->display_order,
            'category' => CategoryResource::make($this->whenLoaded('category')),
            // Inline + shared (library) groups merged in the admin's chosen order.
            // `is_global` tells the form which entries are library references.
            'option_groups' => $this->when(
                $this->relationLoaded('optionGroups') || $this->relationLoaded('sharedOptionGroups'),
                fn () => $this->orderedOptionGroups()->map(fn ($g) => [
                    'id' => $g->id,
                    'is_global' => $g->is_global,
                    'name_en' => $g->name_en,
                    'name_ar' => $g->name_ar,
                    'is_required' => $g->is_required,
                    'is_variant' => $g->is_variant,
                    'max_select' => $g->max_select,
                    'options' => $g->options->map(fn ($o) => [
                        'id' => $o->id,
                        'name_en' => $o->name_en,
                        'name_ar' => $o->name_ar,
                        'price' => $o->price,
                        'discounted_price' => $o->discounted_price,
                        'is_available' => $o->is_available,
                    ])->values(),
                ])->values()
            ),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
