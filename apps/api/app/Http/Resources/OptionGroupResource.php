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
            'is_required' => $this->is_required,
            'is_variant' => $this->is_variant,
            'max_select' => $this->max_select,
            // How many items currently use this shared group (present when counted).
            'items_count' => $this->whenCounted('menuItems'),
            'options' => $this->whenLoaded('options', fn () => $this->options->map(fn ($o) => [
                'id' => $o->id,
                'name_en' => $o->name_en,
                'name_ar' => $o->name_ar,
                'price' => $o->price,
                'is_available' => $o->is_available,
            ])->values()),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
