<?php

namespace App\Http\Resources\Public;

use App\Models\Category;
use App\Support\PublicImageUrl;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Category */
class CategoryPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'image_url' => PublicImageUrl::relative($this->image_url),
            // Serving times. The menu is handed both the answer and the schedule
            // it came from: the answer so the first paint is right without the
            // client having to reason about timezones, the schedule so it can
            // re-evaluate on its own and open the section the minute it is due,
            // rather than looking shut until someone reloads.
            'available_now' => $this->isAvailableNow(),
            'availability_hours' => $this->availability_hours,
            'available_window' => $this->todaysWindow(),
            'items' => MenuItemPublicResource::collection($this->whenLoaded('menuItems')),
        ];
    }
}
