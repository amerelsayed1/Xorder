<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One till (POS-BE-023). Provisioned in the dashboard, claimed by the desktop:
 * the row exists before the machine does, which is what makes fleet tracking
 * structural. States: provisioned → active → revoked.
 *
 * Carries RestaurantScope: dashboard reads are tenant-scoped automatically;
 * the Super Admin fleet views and the unauthenticated claim path run with no
 * tenant context, where the scope is a no-op and every query names its tenant
 * explicitly.
 */
class PosTerminal extends Model
{
    use Auditable, BelongsToRestaurant;

    public const STATE_PROVISIONED = 'provisioned';

    public const STATE_ACTIVE = 'active';

    public const STATE_REVOKED = 'revoked';

    /** How long a rotated-out device token keeps working (POS-BE-011). */
    public const ROTATION_OVERLAP_HOURS = 24;

    /**
     * Descriptive columns only. terminal_id, state, the token hashes and the
     * caches are set exclusively by the provisioning/claim services via
     * forceFill — a terminal's identity and credential must never be
     * mass-assignable from request input.
     */
    protected $fillable = [
        'name',
        'deployment_mode',
        'sync_policy',
    ];

    /** Credential material and caches never leave through serialisation. */
    protected $hidden = [
        'device_token_hash',
        'previous_token_hash',
        'register_response_cache',
    ];

    // Hidden columns are already kept out of the audit diff (see Auditable);
    // the fingerprint is not hidden — it is what a replayed claim is matched on
    // — but it identifies a machine and has no business in a log line.
    protected array $auditExclude = ['fingerprint'];

    protected function casts(): array
    {
        return [
            'claimed_at' => 'datetime',
            'revoked_at' => 'datetime',
            'device_token_rotated_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'oldest_pending_at' => 'datetime',
            'shift_open' => 'boolean',
            'last_catalog_sync_at' => 'datetime',
            'reported_licence_expires_at' => 'datetime',
            'last_licence_check_at' => 'datetime',
            'last_feed_at' => 'datetime',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    /** The licence this till last checked against (R2 telemetry). */
    public function licence(): BelongsTo
    {
        return $this->belongsTo(PosLicence::class, 'licence_id');
    }

    public function pairingCodes(): HasMany
    {
        return $this->hasMany(PosPairingCode::class);
    }

    /** Claimed and trading — the state that holds a licence seat. */
    public function isActive(): bool
    {
        return $this->state === self::STATE_ACTIVE;
    }

    public function isRevoked(): bool
    {
        return $this->state === self::STATE_REVOKED || $this->revoked_at !== null;
    }
}
