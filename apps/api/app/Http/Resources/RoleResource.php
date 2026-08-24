<?php

namespace App\Http\Resources;

use App\Models\Role;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Role */
class RoleResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'name_ar' => $this->name_ar,
            'slug' => $this->slug,
            'is_system' => (bool) $this->is_system,
            'capabilities' => $this->capabilityValues(),
            // Present only when the caller asked for the count (roles list), so
            // the UI can warn before deleting a role that people still hold.
            'users_count' => $this->whenCounted('users'),
        ];
    }
}
