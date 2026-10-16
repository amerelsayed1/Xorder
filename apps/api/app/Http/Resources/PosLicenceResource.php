<?php

namespace App\Http\Resources;

use App\Models\PosLicence;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A POS licence for the Super Admin screens.
 *
 * Never carries the activation key or its hash. The key is returned exactly
 * once, by the issue endpoint, alongside this resource — see LicenceController.
 *
 * @mixin PosLicence
 */
class PosLicenceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'licence_ref' => $this->licence_ref,

            'kind' => $this->kind,

            // Null on an offline licence, and null-safe even when the relation
            // WAS eager-loaded: `whenLoaded` fires on a loaded relation whose
            // value is null, which on a tenant-less licence would dereference
            // it. The list loads it for every row, so this is the normal path,
            // not an edge case.
            'restaurant' => $this->whenLoaded('restaurant', fn () => $this->restaurant ? [
                'id' => $this->restaurant->id,
                'slug' => $this->restaurant->slug,
                'name_en' => $this->restaurant->name_en,
                'name_ar' => $this->restaurant->name_ar,
            ] : null),

            // The customer of an offline licence — who a cloud licence records
            // as a tenant instead. Always present so one list can render both.
            'customer_name' => $this->customer_name,
            'customer_slug' => $this->customer_slug,
            'contact_name' => $this->contact_name,
            'contact_email' => $this->contact_email,
            'contact_phone' => $this->contact_phone,

            // The name to print for this row whichever kind it is, resolved
            // once here so three screens cannot each get it slightly wrong.
            'client_name' => $this->clientName(),
            'client_slug' => $this->clientSlug(),

            'plan' => $this->whenLoaded('plan', fn () => $this->plan ? [
                'id' => $this->plan->id,
                'name' => $this->plan->name,
            ] : null),

            // Whether the activation key can be copied again from the page:
            // false for a licence issued before keys were kept (16 Oct 2026).
            // The key itself is behind its own audited endpoint, never here.
            'key_available' => $this->key_encrypted !== null,

            'state' => $this->state(),
            // R2: what the operator set, and where the till gets its verdict.
            // `verdict` is exactly what /license/check would answer now.
            'status' => $this->status ?? PosLicence::STATUS_ACTIVE,
            'enforcement' => $this->enforcement ?? PosLicence::ENFORCEMENT_ONLINE,
            'verdict' => $this->verdict(),
            'suspended_at' => $this->suspended_at?->toIso8601String(),
            'suspended_reason' => $this->suspended_reason,
            // Null rather than 26,000 for a licence that was sold outright —
            // a countdown to a sentinel is a number nobody should read.
            'days_remaining' => $this->lifetime ? null : $this->daysRemaining(),

            'lifetime' => (bool) $this->lifetime,

            'issued_at' => $this->issued_at?->toIso8601String(),
            'expires_at' => $this->lifetime ? null : $this->expires_at?->toIso8601String(),
            'grace_ends_at' => $this->lifetime ? null : $this->graceEndsAt()->toIso8601String(),

            'grace_days' => $this->grace_days,
            'warn_days' => $this->warn_days,
            'max_terminals' => $this->max_terminals,
            'max_users' => $this->max_users,
            'max_offline_days' => $this->max_offline_days,

            'features' => $this->features ?? [],
            'modes' => $this->modes ?? [],
            'branch_ids' => $this->branch_ids ?? [],
            'fingerprints' => $this->fingerprints ?? [],

            'key_id' => $this->key_id,
            'key_last_four' => $this->key_last_four,

            'superseded_by_id' => $this->superseded_by_id,
            'revoked_at' => $this->revoked_at?->toIso8601String(),
            'revoked_reason' => $this->revoked_reason,
            'activated_at' => $this->activated_at?->toIso8601String(),

            'notes' => $this->notes,

            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
