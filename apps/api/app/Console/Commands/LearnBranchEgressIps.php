<?php

namespace App\Console\Commands;

use App\Models\Branch;
use App\Services\BranchEgressIpService;
use Illuminate\Console\Command;

/**
 * Refreshes every branch's learned customer Wi-Fi egress IPs.
 *
 * Runs nightly: consumer lines rotate their public IP every few hours or days,
 * so a value learned once would go stale silently. Re-deriving it from a
 * rolling window of geofence-verified sessions is what keeps the signal alive
 * without ever asking a restaurant owner to look up their IP address.
 */
class LearnBranchEgressIps extends Command
{
    protected $signature = 'branches:learn-egress-ips {--branch= : Only this branch id}';

    protected $description = "Learn each branch's customer Wi-Fi egress IPs from geofence-verified sessions";

    public function handle(BranchEgressIpService $egressIps): int
    {
        $branches = Branch::withoutGlobalScopes()
            ->where('is_active', true)
            ->when($this->option('branch'), fn ($q, $id) => $q->whereKey($id))
            ->get();

        $withIps = 0;

        foreach ($branches as $branch) {
            $learned = $egressIps->learn($branch);

            if ($learned !== []) {
                $withIps++;
                $this->line(sprintf('  branch #%d: %s', $branch->id, implode(', ', $learned)));
            }
        }

        $this->info(sprintf(
            '%d branch(es) scanned, %d with a learned egress IP.',
            $branches->count(),
            $withIps
        ));

        return self::SUCCESS;
    }
}
