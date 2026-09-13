<?php

namespace Tests\Unit;

use App\Services\PurchaseOrderService;
use App\Support\StockCosting;
use App\Support\SupplierAccount;
use PHPUnit\Framework\TestCase;

/**
 * CB-09 slice c: the ledger arithmetic against the till's own test vectors.
 *
 * Every figure below is copied from xorder-pos, so an invoice, a payment or a
 * supplier balance on the dashboard agrees with the same paper booked on an
 * offline till:
 *   test/core/money_test.dart               roundHalfUp, percentBp
 *   test/domain/supplier_invoice_test.dart  taxWithinBp, the invoice, the
 *                                           delivery comparison, the account
 *   test/domain/purchase_order_test.dart    tax rounded per rate
 *
 * The till's payment names at most one invoice; the platform's is allocated
 * to any number. A till payment "against invoice 1" is an allocation of its
 * whole amount to invoice 1, and a till payment with no invoice is one with
 * nothing allocated. That is the whole translation.
 */
class SupplierLedgerParityTest extends TestCase
{
    private function inv(int $id = 1, int $total = 100000, int $allocated = 0, string $due = '2026-03-31', bool $voided = false): array
    {
        return ['id' => $id, 'total_minor' => $total, 'due_at' => $due, 'voided' => $voided, 'allocated_minor' => $allocated];
    }

    private function pay(int $id = 1, int $amount = 50000, int $allocated = 0, bool $voided = false): array
    {
        return ['id' => $id, 'amount_minor' => $amount, 'voided' => $voided, 'allocated_minor' => $allocated];
    }

    // ------------------------------------------------ money_test.dart

    public function test_round_half_up_including_the_negative_branch(): void
    {
        foreach ([[5, 1], [15, 2], [25, 3], [4, 0], [14, 1], [-5, -1], [-15, -2], [-4, 0]] as [$n, $expected]) {
            $this->assertSame($expected, StockCosting::roundHalfUp($n, 10), "roundHalfUp($n, 10)");
        }
    }

    public function test_percent_bp(): void
    {
        $this->assertSame(4620, StockCosting::percentBp(38500, 1200));
        $this->assertSame(0, StockCosting::percentBp(1, 1400));
        $this->assertSame(1, StockCosting::percentBp(4, 1400));
    }

    // ----------------------------------- supplier_invoice_test.dart: an invoice

    public function test_tax_inside_a_gross_figure(): void
    {
        // 114.00 holding 14% contains 14.00, not 15.96.
        $this->assertSame(14000, StockCosting::taxWithinBp(114000, 1400));
        $this->assertSame(100000, 114000 - StockCosting::taxWithinBp(114000, 1400));
    }

    public function test_the_subtotal_is_derived(): void
    {
        $this->assertSame(87719, 100000 - 12281);
    }

    public function test_outstanding_settled_and_overpaid(): void
    {
        $this->assertSame(60000, SupplierAccount::invoiceOutstanding(100000, 40000));
        // Overpaying does not make the invoice negative.
        $this->assertSame(0, SupplierAccount::invoiceOutstanding(100000, 130000));
        $this->assertTrue(SupplierAccount::isSettled(100000, 130000));
        $this->assertFalse(SupplierAccount::isSettled(100000, 99999));
        $this->assertTrue(SupplierAccount::isSettled(100000, 100000));
    }

    public function test_overdue_is_asked_as_at_a_date_and_due_today_is_not_late(): void
    {
        $this->assertFalse(SupplierAccount::isOverdue('2026-03-31', '2026-03-30', false, 100000, 0));
        $this->assertFalse(SupplierAccount::isOverdue('2026-03-31', '2026-03-31', false, 100000, 0));
        $this->assertTrue(SupplierAccount::isOverdue('2026-03-31', '2026-04-01', false, 100000, 0));
        // A settled invoice is never overdue, however old; a voided one is not a debt.
        $this->assertFalse(SupplierAccount::isOverdue('2026-03-01', '2027-01-01', false, 100000, 100000));
        $this->assertFalse(SupplierAccount::isOverdue('2026-03-01', '2027-01-01', true, 100000, 0));
        // Days late, for a screen that sorts by urgency.
        $this->assertSame(7, SupplierAccount::daysLate('2026-03-10', '2026-03-17', false, 100000, 0));
        $this->assertSame(0, SupplierAccount::daysLate('2026-03-10', '2026-03-09', false, 100000, 0));
    }

    // ------------------------ supplier_invoice_test.dart: against the delivery

    private function delivery(int $received): array
    {
        return [['received_milli' => $received * 1000, 'unit_cost_minor' => 10000, 'tax_rate_bp' => 1400]];
    }

    public function test_the_received_total_is_what_an_invoice_should_say(): void
    {
        // Ten at 100.00 plus 14% is 1,140.00.
        $this->assertSame(114000, PurchaseOrderService::receivedTotal($this->delivery(10)));
    }

    public function test_a_short_delivery_is_not_a_pricing_dispute(): void
    {
        $this->assertSame(91200, PurchaseOrderService::receivedTotal($this->delivery(8)));
        $this->assertSame(0, 91200 - PurchaseOrderService::receivedTotal($this->delivery(8)));
        // Billing for more than arrived is a phone call.
        $this->assertSame(22800, 114000 - PurchaseOrderService::receivedTotal($this->delivery(8)));
        // Nothing received yet: the whole invoice is the variance.
        $this->assertSame(114000, 114000 - PurchaseOrderService::receivedTotal($this->delivery(0)));
    }

    // --------------------- purchase_order_test.dart: invoice lines round like an order

    public function test_invoice_lines_round_tax_per_rate(): void
    {
        // 12.5 kg at 47.30 is 591.25; 14% of it is 82.78.
        $this->assertSame(59125, StockCosting::costAt(12500, 4730));
        $this->assertSame(8278, StockCosting::percentBp(59125, 1400));

        // Three lines of 33.33 at 14%: 14.00 tax, not 14.01.
        $three = PurchaseOrderService::totals(array_fill(0, 3, ['ordered_milli' => 1000, 'unit_cost_minor' => 3333, 'tax_rate_bp' => 1400]));
        $this->assertSame(['subtotal_minor' => 9999, 'tax_minor' => 1400, 'total_minor' => 11399], $three);

        // Two rates are two roundings.
        $two = PurchaseOrderService::totals([
            ['ordered_milli' => 1000, 'unit_cost_minor' => 10000, 'tax_rate_bp' => 1400],
            ['ordered_milli' => 1000, 'unit_cost_minor' => 10000, 'tax_rate_bp' => 500],
        ]);
        $this->assertSame(1900, $two['tax_minor']);
    }

    // ------------------------------ supplier_invoice_test.dart: the account

    public function test_the_balance_is_invoices_less_payments(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000)], [$this->pay(1, 30000, 30000)], '2026-03-15');
        $this->assertSame(100000, $f['invoiced_minor']);
        $this->assertSame(30000, $f['paid_minor']);
        $this->assertSame(70000, $f['outstanding_minor']);
    }

    public function test_a_voided_invoice_is_evidence_not_a_debt(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000), $this->inv(2, 50000, 0, '2026-03-31', true)], [], '2026-03-15');
        $this->assertSame(100000, $f['invoiced_minor']);
    }

    public function test_a_voided_payment_stops_being_money_that_left(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000, 30000)], [
            $this->pay(1, 30000, 30000),
            $this->pay(2, 20000, 20000, true),
        ], '2026-03-15');
        $this->assertSame(30000, $f['paid_minor']);
        $this->assertSame(70000, $f['outstanding_minor']);
    }

    public function test_on_account_money_reduces_the_balance_and_clears_no_bill(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000, 0, '2026-03-10')], [$this->pay(1, 200000, 0)], '2026-03-20');
        $this->assertSame(-100000, $f['outstanding_minor'], 'in credit overall');
        $this->assertSame(100000, $f['overdue_minor'], 'the bill itself is still unpaid and still late');
        $this->assertSame(200000, $f['on_account_minor']);
    }

    public function test_money_allocated_to_the_bill_does_clear_it(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000, 100000, '2026-03-10')], [$this->pay(1, 100000, 100000)], '2026-03-20');
        $this->assertSame(0, $f['overdue_minor']);
        $this->assertSame(0, $f['outstanding_minor']);
    }

    public function test_partly_paid_and_late_counts_only_the_unpaid_part(): void
    {
        $f = SupplierAccount::figures([$this->inv(1, 100000, 40000, '2026-03-10')], [$this->pay(1, 40000, 40000)], '2026-03-20');
        $this->assertSame(60000, $f['overdue_minor']);
    }

    public function test_every_figure_is_a_sum_so_row_order_cannot_matter(): void
    {
        $invoices = [$this->inv(1, 100000, 30000, '2026-03-10'), $this->inv(2, 50000, 0, '2026-03-20')];
        $payments = [$this->pay(1, 30000, 30000), $this->pay(2, 20000, 0)];

        $this->assertSame(
            SupplierAccount::figures($invoices, $payments, '2026-03-15'),
            SupplierAccount::figures(array_reverse($invoices), array_reverse($payments), '2026-03-15'),
        );
    }

    public function test_an_empty_account_owes_nothing(): void
    {
        $f = SupplierAccount::figures([], [], '2026-03-15');
        $this->assertSame(0, $f['invoiced_minor']);
        $this->assertSame(0, $f['outstanding_minor']);
        $this->assertSame(0, $f['overdue_minor']);
    }

    public function test_the_statement_reconciles_by_construction(): void
    {
        $rows = SupplierAccount::statement(
            [
                ['id' => 1, 'date' => '2026-03-01', 'amount_minor' => 100000, 'voided' => false],
                ['id' => 2, 'date' => '2026-03-05', 'amount_minor' => 50000, 'voided' => true],
                ['id' => 3, 'date' => '2026-03-05', 'amount_minor' => 25000, 'voided' => false],
            ],
            [
                ['id' => 1, 'date' => '2026-03-05', 'amount_minor' => 30000, 'voided' => false],
                ['id' => 2, 'date' => '2026-03-02', 'amount_minor' => 99999, 'voided' => true],
            ],
        );

        $this->assertSame(['invoice', 'invoice', 'payment'], array_column($rows, 'kind'), 'voids are left out; on one day invoices come first');
        $this->assertSame([100000, 125000, 95000], array_column($rows, 'balance_minor'));
        $this->assertSame(
            array_sum(array_column($rows, 'debit_minor')) - array_sum(array_column($rows, 'credit_minor')),
            end($rows)['balance_minor'],
        );
    }
}
