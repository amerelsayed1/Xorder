<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * XORD-015: a place the business keeps money — cash, bank or e-wallet — shared
 * by the whole business (`branch_id` null) or tied to one branch.
 *
 * Never deleted: DELETE deactivates, so anything that later names an account
 * keeps a row to point at. `currency` is set by the server from the
 * restaurant, never from input, so it is not fillable.
 */
class FinancialAccount extends Model
{
    use Auditable, BelongsToRestaurant;

    public const KINDS = ['cash', 'bank', 'wallet'];

    /**
     * Which account kinds a payment method of each kind may pay into (owner,
     * 2026-10-26): cash into a cash account, a card into a bank. `external` is
     * a card taken on the bank's own terminal — the till already reads it as a
     * card — so it pays into a bank too. `other` has no natural type, so any
     * account will do (null).
     *
     * `wallet` is an e-wallet method (InstaPay and the like) and pays into a
     * wallet account, as it does on an offline till. This is the same table as
     * the till's `AccountRules.kindsFor`, over the platform's vocabulary, and a
     * test on each side holds them together.
     *
     * @var array<string, list<string>|null>
     */
    public const KINDS_FOR_TENDER = [
        'cash' => ['cash'],
        'card' => ['bank'],
        'wallet' => ['wallet'],
        'external' => ['bank'],
        'other' => null,
    ];

    /** The account kinds a method of [$tenderKind] may pay into; null = any. */
    public static function kindsForTender(?string $tenderKind): ?array
    {
        // A kind this build does not know is treated like `other`.
        return self::KINDS_FOR_TENDER[$tenderKind] ?? null;
    }

    /** May an account of this kind be offered to, and saved for, that method? */
    public function fitsTender(?string $tenderKind): bool
    {
        $allowed = self::kindsForTender($tenderKind);

        return $allowed === null || in_array($this->kind, $allowed, true);
    }

    protected $fillable = ['branch_id', 'name', 'kind', 'reference_label', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
