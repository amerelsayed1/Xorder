<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\MenuItem */
class MenuItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'restaurant_id' => $this->restaurant_id,
            'category_id' => $this->category_id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'price' => $this->price,
            'discounted_price' => $this->discounted_price,
            'image_url' => $this->image_url,
            'is_available' => $this->is_available,
            'is_featured' => $this->is_featured,
            'display_order' => $this->display_order,
            'category' => CategoryResource::make($this->whenLoaded('category')),
            'option_groups' => $this->whenLoaded('optionGroups', fn () => $this->optionGroups->map(fn ($g) => [
                'id' => $g->id,
                'name_en' => $g->name_en,
                'name_ar' => $g->name_ar,
                'is_required' => $g->is_required,
                'max_select' => $g->max_select,
                'options' => $g->options->map(fn ($o) => [
                    'id' => $o->id,
                    'name_en' => $o->name_en,
                    'name_ar' => $o->name_ar,
                    'price' => $o->price,
                    'is_available' => $o->is_available,
                ])->values(),
            ])->values()),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
