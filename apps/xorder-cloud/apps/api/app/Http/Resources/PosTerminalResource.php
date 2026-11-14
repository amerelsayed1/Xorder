<?php

namespace App\Http\Resources;

use App\Models\PosTerminal;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Dashboard + fleet view of a terminal. Credential material is $hidden on the
 * model and never appears here.
 *
 * @mixin PosTerminal
 */
class PosTerminalResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'terminal_id' => $this->terminal_id,
            'name' => $this->name,
            'branch_id' => $this->branch_id,
            // Both controllers already eager-load these; not serialising them
            // made the eager load pure waste and left every fleet table
            // rendering "#3" where a branch name belongs.
            'branch' => $this->whenLoaded('branch', fn () => [
                'id' => $this->branch->id,
                'name_en' => $this->branch->name_en,
                'name_ar' => $this->branch->name_ar,
                'code' => $this->branch->code,
            ]),
            'restaurant' => $this->whenLoaded('restaurant', fn () => [
                'id' => $this->restaurant->id,
                'name_en' => $this->restaurant->name_en,
                'name_ar' => $this->restaurant->name_ar,
                'slug' => $this->restaurant->slug,
            ]),
            'state' => $this->state,
            'platform' => $this->platform,
            'app_version' => $this->app_version,
            'deployment_mode' => $this->deployment_mode,
            'sync_policy' => $this->sync_policy,
            'claimed_at' => $this->claimed_at?->toIso8601String(),
            'revoked_at' => $this->revoked_at?->toIso8601String(),
            'last_seen_at' => $this->last_seen_at?->toIso8601String(),
            'pending_count' => $this->pending_count,
            'oldest_pending_at' => $this->oldest_pending_at?->toIso8601String(),
            'shift_open' => $this->shift_open,
            'clock_offset_seconds' => $this->clock_offset_seconds,
            'last_catalog_sync_at' => $this->last_catalog_sync_at?->toIso8601String(),
            'reported_licence_expires_at' => $this->reported_licence_expires_at?->toIso8601String(),
            'licence_id' => $this->licence_id,
            'last_licence_check_at' => $this->last_licence_check_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            // Only the two terminal lists compute it (PosProvisioningService::
            // withMoneyHistory); every other response keeps its shape. True
            // means delete() refuses with TERMINAL_HAS_HISTORY (XORD-042).
            'has_money_history' => $this->when(
                array_key_exists('has_money_history', $this->resource->getAttributes()),
                fn () => (bool) $this->resource->getAttributes()['has_money_history'],
            ),
        ];
    }
}
