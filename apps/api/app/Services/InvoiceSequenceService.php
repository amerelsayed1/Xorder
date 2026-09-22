<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\InvoiceSequence;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;

/**
 * POS-BE-008: {branch.code}-{YYYY}-{NNNNNN}, sequenced per (tenant, branch,
 * period), concurrency-safe.
 *
 * MUST be called inside the order-creation transaction: the row lock is what
 * makes two concurrent tills impossible to double-issue. A replayed
 * client_transaction_id never reaches here — the number is stored on the
 * order and replays read it back (idempotency never consumes a number).
 *
 * `$series` (POS-BE-010) puts a document class in its OWN bucket: a credit
 * note is `CN-MAADI-2026-000001` counted in period `CN-2026`, so refunds never
 * consume invoice numbers and a gap in the invoice series stays meaningful to
 * an auditor. The period column is 10 chars, which `CN-2026-09` exactly fits.
 */
class InvoiceSequenceService
{
    public function next(Branch $branch, Carbon $at, array $config, string $series = ''): string
    {
        $reset = $config['reset'] ?? 'yearly';
        $padding = (int) ($config['padding'] ?? 6);

        $period = match ($reset) {
            'monthly' => $at->format('Y-m'),
            'never' => 'all',
            default => $at->format('Y'),
        };

        if ($series !== '') {
            $period = $series.'-'.$period;
        }

        // firstOrCreate would race two tills to the same (branch, period) row;
        // the unique index turns the loser into a retry of the locked read.
        $sequence = InvoiceSequence::withoutGlobalScopes()
            ->where('restaurant_id', $branch->restaurant_id)
            ->where('branch_id', $branch->id)
            ->where('period', $period)
            ->lockForUpdate()
            ->first();

        if ($sequence === null) {
            try {
                $sequence = (new InvoiceSequence)->forceFill([
                    'restaurant_id' => $branch->restaurant_id,
                    'branch_id' => $branch->id,
                    'period' => $period,
                    'next_value' => 1,
                ]);
                $sequence->save();
            } catch (UniqueConstraintViolationException) {
                $sequence = InvoiceSequence::withoutGlobalScopes()
                    ->where('restaurant_id', $branch->restaurant_id)
                    ->where('branch_id', $branch->id)
                    ->where('period', $period)
                    ->lockForUpdate()
                    ->firstOrFail();
            }
        }

        $number = $sequence->next_value;
        $sequence->forceFill(['next_value' => $number + 1])->save();

        $prefix = ($config['prefix_source'] ?? 'branch_code') === 'branch_code'
            ? ($branch->code ?: 'BR'.$branch->id)
            : (string) ($config['prefix'] ?? 'INV');

        if ($series !== '') {
            $prefix = $series.'-'.$prefix;
        }

        return sprintf('%s-%s-%s', $prefix, $at->format('Y'), str_pad((string) $number, $padding, '0', STR_PAD_LEFT));
    }
}
