<?php

namespace App\Support;

/**
 * CB-09 slice c: what a supplier's account comes to, from its invoices and
 * payments. A port of the till's SupplierAccount / SupplierInvoice arithmetic
 * (xorder-pos lib/domain/models/supplier_invoice.dart), generalised from "a
 * payment names at most one invoice" to "a payment is allocated to any number
 * of invoices".
 *
 * Pure functions over plain arrays, so the till's own test vectors run
 * straight through it (Tests\Unit\SupplierLedgerParityTest), and
 * SupplierAccountService only has to load rows.
 *
 * EVERY FIGURE IS A SUM, never a fold, so the order the rows are read in can't
 * change an answer:
 *
 *   invoiced     Σ total of live invoices
 *   paid         Σ amount of live payments
 *   outstanding  invoiced − paid                (negative = in credit)
 *   overdue      Σ over live invoices due BEFORE as-of of (total − allocated)
 *   on account   Σ over live payments of (amount − allocated)
 *
 * On-account money reduces `outstanding` and does NOT reduce `overdue`: nobody
 * said which bill it was for, and guessing would make the answer depend on the
 * order of the rows (the till's decision, and its test).
 *
 * "Allocated" always means allocations from LIVE payments only; a voided
 * payment's allocations stop counting, which is what makes a mistyped payment
 * correctable. Because the ledger service refuses (a) allocations above an
 * invoice's total and (b) voiding an invoice that has live allocations, this
 * identity holds exactly and SupplierLedgerTest asserts it:
 *
 *   outstanding = Σ open-invoice outstanding − on account
 *
 * @phpstan-type Invoice array{id:int, total_minor:int, due_at:string, voided:bool, allocated_minor:int}
 * @phpstan-type Payment array{id:int, amount_minor:int, voided:bool, allocated_minor:int}
 */
final class SupplierAccount
{
    /**
     * What is still owed on one invoice. Never negative: paying more than a
     * bill asks for is a credit on the ACCOUNT, not a negative bill.
     */
    public static function invoiceOutstanding(int $totalMinor, int $allocatedMinor): int
    {
        return max(0, $totalMinor - $allocatedMinor);
    }

    public static function isSettled(int $totalMinor, int $allocatedMinor): bool
    {
        return $allocatedMinor >= $totalMinor;
    }

    /**
     * Whether the terms have run out with money still on it, as at a date.
     * "Due today is not late": overdue only once as-of is AFTER the due date.
     * Dates are Y-m-d strings, which compare correctly as strings.
     */
    public static function isOverdue(string $dueAt, string $asOf, bool $voided, int $totalMinor, int $allocatedMinor): bool
    {
        return ! $voided && ! self::isSettled($totalMinor, $allocatedMinor) && $asOf > $dueAt;
    }

    /** How many whole days late, or zero. */
    public static function daysLate(string $dueAt, string $asOf, bool $voided, int $totalMinor, int $allocatedMinor): int
    {
        if (! self::isOverdue($dueAt, $asOf, $voided, $totalMinor, $allocatedMinor)) {
            return 0;
        }

        return (int) (new \DateTimeImmutable($dueAt.' 00:00:00', new \DateTimeZone('UTC')))
            ->diff(new \DateTimeImmutable($asOf.' 00:00:00', new \DateTimeZone('UTC')))
            ->days;
    }

    /**
     * @param  list<Invoice>  $invoices
     * @param  list<Payment>  $payments
     * @return array{invoiced_minor:int, paid_minor:int, outstanding_minor:int, overdue_minor:int, on_account_minor:int, open_invoices:int, overdue_invoices:int}
     */
    public static function figures(array $invoices, array $payments, string $asOf): array
    {
        $invoiced = 0;
        $overdue = 0;
        $open = 0;
        $late = 0;
        foreach ($invoices as $i) {
            if ($i['voided']) {
                continue;
            }
            $invoiced += $i['total_minor'];
            if (! self::isSettled($i['total_minor'], $i['allocated_minor'])) {
                $open++;
            }
            if (self::isOverdue($i['due_at'], $asOf, false, $i['total_minor'], $i['allocated_minor'])) {
                $overdue += self::invoiceOutstanding($i['total_minor'], $i['allocated_minor']);
                $late++;
            }
        }

        $paid = 0;
        $onAccount = 0;
        foreach ($payments as $p) {
            if ($p['voided']) {
                continue;
            }
            $paid += $p['amount_minor'];
            $onAccount += $p['amount_minor'] - $p['allocated_minor'];
        }

        return [
            'invoiced_minor' => $invoiced,
            'paid_minor' => $paid,
            'outstanding_minor' => $invoiced - $paid,
            'overdue_minor' => $overdue,
            'on_account_minor' => $onAccount,
            'open_invoices' => $open,
            'overdue_invoices' => $late,
        ];
    }

    /**
     * The statement: live invoices as debits and live payments as credits,
     * by date, with a running balance. On one day invoices come before
     * payments, then by id, so the order is total and repeatable.
     *
     * Reconciles by construction: the last row's balance is exactly
     * figures()['outstanding_minor'], because both are Σ debits − Σ credits
     * over the same live rows.
     *
     * @param  list<array{id:int, date:string, amount_minor:int, voided:bool}+array<string,mixed>>  $invoices
     * @param  list<array{id:int, date:string, amount_minor:int, voided:bool}+array<string,mixed>>  $payments
     * @return list<array<string,mixed>>
     */
    public static function statement(array $invoices, array $payments): array
    {
        $rows = [];
        foreach ($invoices as $i) {
            if (! $i['voided']) {
                $rows[] = $i + ['kind' => 'invoice', 'debit_minor' => $i['amount_minor'], 'credit_minor' => 0];
            }
        }
        foreach ($payments as $p) {
            if (! $p['voided']) {
                $rows[] = $p + ['kind' => 'payment', 'debit_minor' => 0, 'credit_minor' => $p['amount_minor']];
            }
        }

        usort($rows, fn ($a, $b) => [$a['date'], $a['kind'] === 'invoice' ? 0 : 1, $a['id']]
            <=> [$b['date'], $b['kind'] === 'invoice' ? 0 : 1, $b['id']]);

        $balance = 0;
        foreach ($rows as $k => $row) {
            $balance += $row['debit_minor'] - $row['credit_minor'];
            $rows[$k]['balance_minor'] = $balance;
            unset($rows[$k]['voided'], $rows[$k]['amount_minor']);
        }

        return $rows;
    }
}
