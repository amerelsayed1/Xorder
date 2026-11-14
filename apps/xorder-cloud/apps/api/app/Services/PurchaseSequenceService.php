<?php

namespace App\Services;

use App\Models\PurchaseSequence;
use Illuminate\Support\Carbon;

/**
 * CB-09 slice b: PO-{YYYY}-{NNNNNN}, per business per year, gap-free.
 *
 * MUST be called inside the send transaction, after the order row is
 * locked: the sequence row lock is what makes two concurrent sends
 * impossible to double-issue, and a send that later fails rolls the
 * increment back with it, so no number is ever skipped.
 *
 * The row is created with insertOrIgnore (the grammar's portable "insert or
 * ignore" / "on conflict do nothing") and then read FOR UPDATE. Unlike
 * catching a unique violation, that never leaves a PostgreSQL transaction
 * aborted.
 */
class PurchaseSequenceService
{
    public function next(int $restaurantId, Carbon $at): string
    {
        $period = $at->format('Y');

        PurchaseSequence::query()->insertOrIgnore([
            'restaurant_id' => $restaurantId,
            'period' => $period,
            'next_value' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $sequence = PurchaseSequence::withoutGlobalScopes()
            ->where('restaurant_id', $restaurantId)
            ->where('period', $period)
            ->lockForUpdate()
            ->firstOrFail();

        $number = $sequence->next_value;
        $sequence->forceFill(['next_value' => $number + 1])->save();

        return sprintf('PO-%s-%s', $period, str_pad((string) $number, 6, '0', STR_PAD_LEFT));
    }
}
