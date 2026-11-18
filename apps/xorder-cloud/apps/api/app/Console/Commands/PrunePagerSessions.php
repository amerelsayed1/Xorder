<?php

namespace App\Console\Commands;

use App\Services\PagerSessionService;
use Illuminate\Console\Command;

/**
 * Deletes dead guest-paging pairing sessions (docs/features/guest-paging-shared-qr):
 * codes nobody claimed, and paired sessions older than the order-number page's
 * lifetime. The table is small and indexed, so one pass is enough.
 */
class PrunePagerSessions extends Command
{
    protected $signature = 'pager:prune';

    protected $description = 'Delete expired guest-paging pairing sessions';

    public function handle(PagerSessionService $pager): int
    {
        $this->info('Deleted '.$pager->prune().' pairing sessions.');

        return self::SUCCESS;
    }
}
