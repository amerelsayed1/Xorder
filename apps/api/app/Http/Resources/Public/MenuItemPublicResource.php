<?php

namespace App\Http\Resources\Public;

use App\Models\MenuItem;
use App\Support\PublicImageUrl;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public, customer-facing item shape. Exposes only menu data — no internal
 * ids beyond what the page needs, no timestamps, no tenant internals.
 *
 * @mixin MenuItem
 */
class MenuItemPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // An item priced by a size group advertises its DEFAULT size — the one
        // the modal opens on — so the card can never quote a figure no
        // selection charges. Falls back to the item's own columns otherwise.
        [$price, $discountedPrice] = $this->resource->displayPricing();

        return [
            'id' => $this->id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'price' => $price,
            'discounted_price' => $discountedPrice,
            'image_url' => PublicImageUrl::relative($this->image_url),
            'is_available' => $this->is_available,
            'is_featured' => $this->is_featured,
            // Inline + shared (library) groups merged in the item's display order.
            'option_groups' => $this->when(
                $this->relationLoaded('optionGroups') || $this->relationLoaded('sharedOptionGroups'),
                fn () => $this->orderedOptionGroups()->map(fn ($g) => [
                    // The diner-facing heading, which is a separate field from
                    // the name the group is filed under in the Extras library
                    // (falling back to it when unset). Emitted under the same
                    // keys the menu already reads — the public shape is "the
                    // name you show", wherever it comes from.
                    'name_en' => $g->publicName('en'),
                    'name_ar' => $g->publicName('ar'),
                    'is_required' => $g->is_required,
                    'is_variant' => $g->is_variant,
                    'max_select' => $g->max_select,
                    'options' => $g->options->where('is_available', true)->map(fn ($o) => [
                        'name_en' => $o->name_en,
                        'name_ar' => $o->name_ar,
                        'price' => $o->price,
                        'discounted_price' => $o->discounted_price,
                    ])->values(),
                ])->values()
            ),
        ];
    }
}
