<?php

namespace App\Support;

use OverflowException;

/**
 * CB-09 D9: what stock costs after something arrives at a different price.
 * A line-for-line PHP port of the till's moving average
 * (xorder-pos lib/domain/services/stock_costing.dart), with the same integer
 * formulas and the same three rounding points:
 *
 *   1. costAt       roundHalfUp(milli × unitCostMinor, 1000)       quantity.dart
 *   2. percentBp    roundHalfUp(minor × bp, 10000)                 money.dart
 *   3. the average  roundHalfUp((valueOnHand + valueArriving) × 1000,
 *                               onHand + arrived)                  stock_costing.dart
 *
 * so a delivery booked on the dashboard and the same delivery booked on an
 * offline till agree to the piastre. Tests\Unit\StockCostingParityTest runs
 * the till's own test vectors through this class.
 *
 * Money is integer minor units; a quantity is integer thousandths. There is no
 * float anywhere in here, and no unit: this class never converts units, and
 * the caller (ReceivingService) refuses a receipt whose unit differs from the
 * stock it would join.
 *
 * PHP turns an int that overflows into a float silently, which would put
 * binary floating point exactly where this class exists to keep it out. So
 * every multiplication and addition is checked and throws rather than
 * degrading. PHP_INT_MAX is 9.2e18; the largest realistic product here is a
 * few 1e16, so the check is a tripwire, not a limit anyone meets.
 */
final class StockCosting
{
    /**
     * Integer half-up division. Negative numerators round half AWAY from
     * zero, as the till's roundHalfUp does (lib/core/money/rounding.dart).
     */
    public static function roundHalfUp(int $numerator, int $denominator): int
    {
        if ($denominator <= 0) {
            throw new \InvalidArgumentException("denominator must be positive, got {$denominator}");
        }

        if ($numerator >= 0) {
            return intdiv(self::add(self::mul($numerator, 2), $denominator), $denominator * 2);
        }

        return -intdiv(self::add(self::mul(-$numerator, 2), $denominator), $denominator * 2);
    }

    /** What $milli thousandths cost at $unitCostMinor each: the one rounding point for a line. */
    public static function costAt(int $milli, int $unitCostMinor): int
    {
        return self::roundHalfUp(self::mul($milli, $unitCostMinor), 1000);
    }

    /** A rate in basis points (1400 = 14%) applied to an amount, rounded half-up once. */
    public static function percentBp(int $minor, int $basisPoints): int
    {
        return self::roundHalfUp(self::mul($minor, $basisPoints), 10000);
    }

    /**
     * The position after $receivedMilli arrives at $unitCostMinor each.
     *
     * - Receiving nothing (or a negative) is a no-op.
     * - Nothing on hand, or a NEGATIVE on hand: the arriving cost wins. The
     *   quantity still settles the debt.
     * - Otherwise the quantity-weighted average, rounded half-up once.
     *
     * @return array{milli:int, cost:int}
     */
    public static function receive(int $onHandMilli, int $averageCostMinor, int $receivedMilli, int $unitCostMinor): array
    {
        if ($receivedMilli <= 0) {
            return ['milli' => $onHandMilli, 'cost' => $averageCostMinor];
        }

        $settled = self::add($onHandMilli, $receivedMilli);

        if ($onHandMilli <= 0) {
            return ['milli' => $settled, 'cost' => $unitCostMinor];
        }

        $valueOnHand = self::costAt($onHandMilli, $averageCostMinor);
        $valueArriving = self::costAt($receivedMilli, $unitCostMinor);

        return [
            'milli' => $settled,
            'cost' => self::roundHalfUp(self::mul(self::add($valueOnHand, $valueArriving), 1000), $settled),
        ];
    }

    /**
     * The position after $issuedMilli leaves (a sale or waste). The cost never
     * moves, and the quantity may go negative. Unused in slice b (only
     * receipts are written); ported now so slice d starts from the same code.
     *
     * @return array{milli:int, cost:int}
     */
    public static function issue(int $onHandMilli, int $averageCostMinor, int $issuedMilli): array
    {
        if ($issuedMilli <= 0) {
            return ['milli' => $onHandMilli, 'cost' => $averageCostMinor];
        }

        return ['milli' => $onHandMilli - $issuedMilli, 'cost' => $averageCostMinor];
    }

    /** What $issuedMilli cost, at the average held BEFORE the issue. */
    public static function costOfGoods(int $averageCostMinor, int $issuedMilli): int
    {
        return self::costAt($issuedMilli, $averageCostMinor);
    }

    /** What a position is worth: quantity × average, rounded once. Negative stock is a negative value. */
    public static function value(int $onHandMilli, int $averageCostMinor): int
    {
        return self::costAt($onHandMilli, $averageCostMinor);
    }

    private static function mul(int $a, int $b): int
    {
        $r = $a * $b;
        if (! is_int($r)) {
            throw new OverflowException('Stock costing overflowed a 64-bit integer.');
        }

        return $r;
    }

    private static function add(int $a, int $b): int
    {
        $r = $a + $b;
        if (! is_int($r)) {
            throw new OverflowException('Stock costing overflowed a 64-bit integer.');
        }

        return $r;
    }
}
