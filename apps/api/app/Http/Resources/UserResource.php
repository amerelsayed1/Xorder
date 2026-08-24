<?php

namespace App\Http\Resources;

use App\Enums\RoleEnum;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin User */
class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'username' => $this->username,
            'email' => $this->email,
            'role' => $this->role->value,
            'restaurant_id' => $this->restaurant_id,
            'status' => $this->status->value,
            // The custom in-restaurant role (staff accounts only) and the
            // capabilities it grants. `capabilities` is what the dashboard SPA
            // mirrors to hide sections the API would 403 anyway — the server
            // gates stay authoritative. Empty for platform users; the full set
            // for a restaurant owner.
            // Whether this account owns the restaurant. The Employees list shows
            // owners as a read-only row: their access is implicit (no Role
            // governs them) and the API refuses every write against them, so
            // the UI must not offer edit or delete controls it cannot honour.
            'is_owner' => $this->role === RoleEnum::RESTAURANT_ADMIN,
            'role_id' => $this->role_id,
            'role_name' => $this->whenLoaded('tenantRole', fn () => $this->tenantRole?->name),
            'role_name_ar' => $this->whenLoaded('tenantRole', fn () => $this->tenantRole?->name_ar),
            'capabilities' => $this->tenantCapabilities(),
            'restaurant' => RestaurantResource::make($this->whenLoaded('restaurant')),
        ];
    }
}
