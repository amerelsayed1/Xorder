<?php

namespace App\Enums;

/**
 * CB-09 slice d: why stock changed other than by a delivery. A CODE, not
 * free text, as for every other reversal in purchasing, so it can be counted
 * later; `other` needs a note.
 *
 * The till reserves the reason scopes `waste` and `adjustment`
 * (reason_code.dart, migration 31's CHECK) but seeds no rows for either, so
 * these lists are the platform's own. Reason lists a business can edit are
 * out of scope, as in slice c.
 *
 * Each reason belongs to one or more entry kinds (the request's `kind`):
 *
 *   opening     opening_balance                         (set by the server)
 *   waste       expired, spoiled, damaged, preparation_error, other
 *   adjustment  entry_error, found, missing, internal_use, other
 *   count       stock_count                             (set by the server)
 *
 * and some only make sense one way: `found` adds stock; `missing` and
 * `internal_use` take it off. The rest go either way.
 */
enum StockAdjustmentReason: string
{
    case OPENING_BALANCE = 'opening_balance';

    case EXPIRED = 'expired';
    case SPOILED = 'spoiled';
    case DAMAGED = 'damaged';
    case PREPARATION_ERROR = 'preparation_error';

    case ENTRY_ERROR = 'entry_error';
    case FOUND = 'found';
    case MISSING = 'missing';
    case INTERNAL_USE = 'internal_use';

    case STOCK_COUNT = 'stock_count';

    case OTHER = 'other';

    /** The entry kinds a request may send. `count` is stored as an `adjustment` movement. */
    public const KINDS = ['opening', 'waste', 'adjustment', 'count'];

    /** @return list<self> the reasons a request of this kind may carry */
    public static function forKind(string $kind): array
    {
        return match ($kind) {
            'opening' => [self::OPENING_BALANCE],
            'waste' => [self::EXPIRED, self::SPOILED, self::DAMAGED, self::PREPARATION_ERROR, self::OTHER],
            'adjustment' => [self::ENTRY_ERROR, self::FOUND, self::MISSING, self::INTERNAL_USE, self::OTHER],
            'count' => [self::STOCK_COUNT],
            default => [],
        };
    }

    /** The one reason a kind implies when the request names none (opening, count). */
    public static function defaultFor(string $kind): ?self
    {
        return match ($kind) {
            'opening' => self::OPENING_BALANCE,
            'count' => self::STOCK_COUNT,
            default => null,
        };
    }

    /** +1 only adds, -1 only takes off, 0 either way. */
    public function direction(): int
    {
        return match ($this) {
            self::FOUND => 1,
            self::MISSING, self::INTERNAL_USE => -1,
            default => 0,
        };
    }

    public function requiresNote(): bool
    {
        return $this === self::OTHER;
    }
}
