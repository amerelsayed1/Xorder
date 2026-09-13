<?php

namespace Tests\Unit;

use App\Services\PurchaseOrderService;
use App\Support\StockCosting;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * CB-09 D9: the PHP moving average gives the till's numbers, to the piastre.
 *
 * Every vector here is copied from the till's own unit tests, with the file
 * named, so a change on either side that breaks agreement fails here:
 *
 *   xorder-pos test/domain/stock_costing_test.dart     receive, issue, costOfGoods, value
 *   xorder-pos test/core/quantity_test.dart            costAt (the line rounding point)
 *   xorder-pos test/domain/purchase_order_test.dart    line tax, order totals per rate, receivedValue
 *
 * The one set NOT from a till test is roundHalfUp's negative branch, which the
 * till has no test for; those rows are derived by hand from the source,
 * lib/core/money/rounding.dart (half away from zero), and say so.
 */
class StockCostingParityTest extends TestCase
{
    /** @return array<string, array{int,int,int,int,int,int}> onHand, avg, received, cost => milli, cost */
    public static function receiveVectors(): array
    {
        return [
            // stock_costing_test.dart, group "the average moves, weighted by quantity"
            'the textbook case' => [10000, 4000, 10000, 5000, 20000, 4500],
            'it is weighted, not a midpoint' => [30000, 4000, 10000, 6000, 40000, 4500],
            'a fractional delivery still lands on a whole piastre' => [7500, 4400, 12500, 4730, 20000, 4606],
            // group "the cases that are not an average"
            'nothing on hand takes the arriving price' => [0, 0, 10000, 4730, 10000, 4730],
            'negative on hand takes it too, and the debt settles' => [-2000, 9999, 10000, 4730, 8000, 4730],
            'receiving nothing changes nothing' => [10000, 4000, 0, 9999, 10000, 4000],
            'a free delivery drops the average' => [10000, 4000, 10000, 0, 20000, 2000],
        ];
    }

    #[DataProvider('receiveVectors')]
    public function test_receive_matches_the_till(int $onHand, int $avg, int $received, int $cost, int $milli, int $expectedCost): void
    {
        $after = StockCosting::receive($onHand, $avg, $received, $cost);

        $this->assertSame($milli, $after['milli']);
        $this->assertSame($expectedCost, $after['cost']);
    }

    public function test_the_value_it_implies_is_the_value_that_went_in(): void
    {
        // stock_costing_test.dart "the value it implies is the value that went in"
        $after = StockCosting::receive(7000, 4400, 3000, 5100);
        $expected = StockCosting::value(7000, 4400) + StockCosting::costAt(3000, 5100);

        $this->assertLessThanOrEqual(1, abs(StockCosting::value($after['milli'], $after['cost']) - $expected));
    }

    public function test_issue_matches_the_till(): void
    {
        // stock_costing_test.dart, group "issuing"
        $this->assertSame(['milli' => 7000, 'cost' => 4500], StockCosting::issue(10000, 4500, 3000));
        $this->assertSame(['milli' => -2000, 'cost' => 4500], StockCosting::issue(1000, 4500, 3000));
        $this->assertSame(['milli' => 10000, 'cost' => 4500], StockCosting::issue(10000, 4500, 0));
    }

    public function test_cost_of_goods_matches_the_till(): void
    {
        // stock_costing_test.dart, group "what it cost to sell"
        $this->assertSame(13500, StockCosting::costOfGoods(4500, 3000));
        $this->assertSame(1110, StockCosting::costOfGoods(3333, 333), '0.333 × 33.33 = 11.0989 → 11.10');
    }

    public function test_valuation_matches_the_till(): void
    {
        // stock_costing_test.dart, group "valuation"
        $this->assertSame(59125, StockCosting::value(12500, 4730));
        $this->assertSame(0, StockCosting::value(0, 0));
        $this->assertSame(-9000, StockCosting::value(-2000, 4500), 'negative stock is worth a negative');
    }

    public function test_cost_at_matches_the_till(): void
    {
        // quantity_test.dart, group "what a line costs"
        $this->assertSame(9460, StockCosting::costAt(2000, 4730));
        $this->assertSame(1575, StockCosting::costAt(333, 4730), '0.333 kg at 47.30 is 15.7509 → 15.75');
        $this->assertSame(2368, StockCosting::costAt(500, 4735), '0.5 at 47.35 is 23.675 → 23.68');
        $this->assertSame(0, StockCosting::costAt(0, 4730));
        $this->assertSame(333 * 3, StockCosting::costAt(100, 3333) * 3);
        $this->assertSame(1000, StockCosting::costAt(300, 3333));
    }

    public function test_line_and_order_totals_match_the_till(): void
    {
        // purchase_order_test.dart
        $this->assertSame(59125, StockCosting::costAt(12500, 4730), 'a fractional quantity rounds once');
        $this->assertSame(8278, StockCosting::percentBp(59125, 1400), 'tax is a share of the line, rounded once');

        $line = fn (int $milli, int $cost, int $bp = 0, int $received = 0) => [
            'ordered_milli' => $milli, 'unit_cost_minor' => $cost, 'tax_rate_bp' => $bp, 'received_milli' => $received,
        ];

        $sum = PurchaseOrderService::totals([$line(2000, 5000), $line(1000, 3000)]);
        $this->assertSame(13000, $sum['subtotal_minor'], 'lines sum');
        $this->assertSame(13000, $sum['total_minor']);

        $perRate = PurchaseOrderService::totals([$line(1000, 3333, 1400), $line(1000, 3333, 1400), $line(1000, 3333, 1400)]);
        $this->assertSame(9999, $perRate['subtotal_minor']);
        $this->assertSame(1400, $perRate['tax_minor'], 'tax rounds per rate, not per line: not 1401');

        $twoRates = PurchaseOrderService::totals([$line(1000, 10000, 1400), $line(1000, 10000, 500)]);
        $this->assertSame(1400 + 500, $twoRates['tax_minor'], 'two rates are two roundings');

        $this->assertSame(0, PurchaseOrderService::totals([])['total_minor'], 'an empty order comes to nothing');

        // "the received value is what the invoice should match": 8 kg at 47.30.
        $this->assertSame(37840, PurchaseOrderService::receivedValue([$line(12500, 4730, 0, 8000)]));
    }

    public function test_round_half_up_negative_branch_from_the_source(): void
    {
        // Not a till test vector: derived from lib/core/money/rounding.dart,
        // which rounds negative numerators half AWAY from zero.
        $this->assertSame(1, StockCosting::roundHalfUp(5, 10));
        $this->assertSame(-1, StockCosting::roundHalfUp(-5, 10));
        $this->assertSame(0, StockCosting::roundHalfUp(-4, 10));
        $this->assertSame(-2, StockCosting::roundHalfUp(-15, 10));
        $this->assertSame(-1575, StockCosting::costAt(-333, 4730), 'the mirror of 1575');
    }

    public function test_an_overflow_throws_instead_of_becoming_a_float(): void
    {
        $this->expectException(\OverflowException::class);
        StockCosting::costAt(PHP_INT_MAX, 2);
    }
}
