<?php

namespace Tests\Unit;

use App\Support\StockCosting;
use PHPUnit\Framework\TestCase;

/**
 * CB-09 slice d: opening stock, waste, adjustments and counts give the till's
 * numbers, to the piastre.
 *
 * Slice d adds no arithmetic. An entry going IN is StockCosting::receive at
 * its unit cost; an entry going OUT is StockCosting::issue at the average.
 * So the vectors are the till's own receive/issue/costOfGoods/value cases,
 * from xorder-pos test/domain/stock_costing_test.dart, read as the slice-d
 * kind each one stands for. Rows marked "composed" chain two of the till's
 * vectors with no new rounding of their own; rows marked "derived" are
 * computed by hand from stock_costing.dart and say so.
 */
class StockAdjustmentParityTest extends TestCase
{
    public function test_opening_stock_enters_like_a_receipt(): void
    {
        // "nothing on hand takes the arriving price": an opening on nothing.
        $this->assertSame(['milli' => 10000, 'cost' => 4730], StockCosting::receive(0, 0, 10000, 4730));

        // "the textbook case": an opening of 10 kg at 50.00 booked after a
        // receipt of 10 kg at 40.00 averages to 45.00, like a second delivery.
        $this->assertSame(['milli' => 20000, 'cost' => 4500], StockCosting::receive(10000, 4000, 10000, 5000));

        // "a fractional delivery still lands on a whole piastre": 7.5 kg of
        // opening stock at 44.00, then 12.5 kg received at 47.30.
        $this->assertSame(['milli' => 20000, 'cost' => 4606], StockCosting::receive(7500, 4400, 12500, 4730));
    }

    public function test_waste_and_negative_adjustments_leave_at_the_average(): void
    {
        // group "issuing": "does not move the cost".
        $this->assertSame(['milli' => 7000, 'cost' => 4500], StockCosting::issue(10000, 4500, 3000));
        // group "what it cost to sell": the value that left, at the average before.
        $this->assertSame(13500, StockCosting::costOfGoods(4500, 3000));
        $this->assertSame(1110, StockCosting::costOfGoods(3333, 333), 'a fractional write-off rounds once: 11.0989 → 11.10');
        // "issuing nothing changes nothing".
        $this->assertSame(['milli' => 10000, 'cost' => 4500], StockCosting::issue(10000, 4500, 0));
    }

    public function test_negative_stock_follows_the_till(): void
    {
        // "is allowed to go negative": writing off 3 kg of 1 kg held.
        $this->assertSame(['milli' => -2000, 'cost' => 4500], StockCosting::issue(1000, 4500, 3000));
        // "negative stock is worth a negative — it is not hidden".
        $this->assertSame(-9000, StockCosting::value(-2000, 4500));
        // "negative on hand takes it too, and the debt settles": the next
        // arrival (receipt, opening, adjustment up or count up) is not
        // averaged against the debt.
        $this->assertSame(['milli' => 8000, 'cost' => 4730], StockCosting::receive(-2000, 9999, 10000, 4730));
        $this->assertSame(['milli' => 8000, 'cost' => 4730], StockCosting::receive(-2000, 4500, 10000, 4730));
    }

    public function test_the_cost_of_a_write_off_is_not_moved_by_a_later_arrival(): void
    {
        // "and not the average after a later delivery moved it".
        $before = ['milli' => 10000, 'cost' => 4500];
        $wasted = StockCosting::costOfGoods($before['cost'], 3000);
        $after = StockCosting::issue($before['milli'], $before['cost'], 3000);
        $next = StockCosting::receive($after['milli'], $after['cost'], 10000, 9000);

        $this->assertSame(13500, $wasted);
        // Derived: (31,500.00 + 90,000.00) × 1000 / 17000 = 71.4706 → 71.47.
        $this->assertSame(['milli' => 17000, 'cost' => 7147], $next);
    }

    public function test_valuation_after_a_mix_of_kinds(): void
    {
        // Composed: opening 7.5 kg at 44.00, received 12.5 kg at 47.30
        // (the till's 46.06), waste 3 kg, then a count finding 16 kg.
        $p = StockCosting::receive(0, 0, 7500, 4400);
        $p = StockCosting::receive($p['milli'], $p['cost'], 12500, 4730);
        $this->assertSame(['milli' => 20000, 'cost' => 4606], $p);

        $p = StockCosting::issue($p['milli'], $p['cost'], 3000);
        $this->assertSame(['milli' => 17000, 'cost' => 4606], $p);
        $this->assertSame(78302, StockCosting::value($p['milli'], $p['cost']), 'valuation: quantity × average, rounded once');

        $p = StockCosting::issue($p['milli'], $p['cost'], 17000 - 16000);
        $this->assertSame(['milli' => 16000, 'cost' => 4606], $p);
        $this->assertSame(73696, StockCosting::value($p['milli'], $p['cost']));
    }

    public function test_a_rise_at_the_average_keeps_the_average(): void
    {
        // Derived: an adjustment up with no cost typed enters at the average
        // held, so (400.00 + 80.00) × 1000 / 12000 = 40.00.
        $this->assertSame(['milli' => 12000, 'cost' => 4000], StockCosting::receive(10000, 4000, 2000, 4000));
        // Derived: 1 kg at 52.00 into 11.5 kg at 40.00 = 512.00 / 12.5 = 40.96.
        $this->assertSame(['milli' => 12500, 'cost' => 4096], StockCosting::receive(11500, 4000, 1000, 5200));
    }
}
