<?php

namespace App\Http\Resources;

use App\Models\AuditLog;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin AuditLog
 */
class AuditLogResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'action' => $this->action,
            'category' => $this->category,
            'description' => $this->description,
            'actor' => [
                'id' => $this->actor_id,
                'name' => $this->actor_name ?: $this->actor?->name,
                'role' => $this->actor_role,
            ],
            'tenant' => $this->restaurant ? [
                'id' => $this->restaurant->id,
                'name' => $this->restaurant->name_en ?: ($this->restaurant->name_ar ?: $this->restaurant->slug),
            ] : null,
            'subject' => $this->auditable_type ? [
                'type' => class_basename($this->auditable_type),
                'id' => $this->auditable_id,
            ] : null,
            'properties' => $this->properties,
            'ip_address' => $this->ip_address,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
