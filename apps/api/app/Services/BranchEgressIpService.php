<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\MenuSession;
use App\Support\EgressIp;

/**
 * Learns and matches the public IP a branch's customer Wi-Fi exits through.
 *
 * A browser cannot tell you which Wi-Fi it is joined to — no web API exposes
 * SSID or BSSID on any platform, and the indirect routes (WebRTC local
 * candidates, probing the LAN) have been closed by browser vendors. The one
 * signal left is not a browser feature at all: the source address of the
 * request. A diner on the branch's guest Wi-Fi arrives from the branch's NAT; a
 * diner on mobile data arrives from their carrier.
 *
 * That makes a match *corroboration of presence, never proof of absence*. Most
 * diners are on mobile data and will legitimately never match, so a miss says
 * nothing and must never deny a session. Two further limits worth remembering
 * before this is given any authority:
 *
 *  - Under CGNAT the branch shares its public IP with other subscribers, so a
 *    match can be produced by someone who was never on the premises.
 *  - Dynamic IPs rotate. Learning from a rolling window is what keeps this
 *    self-healing; a value configured once by hand would silently go stale.
 *
 * The addresses are learned rather than configured: sessions that already
 * passed the branch geofence are known to have been on-premises, so the address
 * they repeatedly arrive from is the branch's own line. No owner setup at all.
 */
class BranchEgressIpService
{
    /**
     * Is this request coming from an address known to be the branch's Wi-Fi?
     *
     * Returns null — not false — when the branch has learned no addresses yet,
     * so callers can tell "not on the branch network" apart from "we have no
     * idea". Never treat false as evidence the diner is elsewhere.
     */
    public function matches(?Branch $branch, ?string $ip): ?bool
    {
        $known = $this->knownAddresses($branch);

        if ($known === []) {
            return null;
        }

        $token = EgressIp::normalize($ip);

        return $token === null ? null : in_array($token, $known, true);
    }

    /**
     * Every address this branch counts as its own: what the owner declared plus
     * what we learned. Either alone is enough to recognise a diner — a branch
     * set up by hand on day one needs no history, and a branch nobody
     * configured still learns on its own.
     *
     * @return list<string>
     */
    public function knownAddresses(?Branch $branch): array
    {
        if ($branch === null) {
            return [];
        }

        $manual = is_array($branch->egress_ips_manual) ? $branch->egress_ips_manual : [];
        $learned = is_array($branch->egress_ips) ? $branch->egress_ips : [];

        return array_values(array_unique([...$manual, ...$learned]));
    }

    /**
     * Replace a branch's owner-declared addresses.
     *
     * Normalised on the way in so they compare identically to what arrives on a
     * live request — otherwise an owner pasting a full IPv6 address would store
     * something no diner could ever match.
     *
     * @param  list<string>  $addresses
     * @return list<string> what was stored, after normalisation and de-duping
     */
    public function setManualAddresses(Branch $branch, array $addresses): array
    {
        $stored = array_values(array_unique(array_filter(
            array_map(fn (string $ip) => EgressIp::normalize(trim($ip)), $addresses),
        )));

        $branch->egress_ips_manual = $stored === [] ? null : $stored;
        $branch->save();

        return $stored;
    }

    /**
     * Read-only presence summary for one branch's dashboard card.
     *
     * The rate is deliberately taken over sessions the question could actually
     * be answered for, not over every session: before an address is learned
     * every session is "unknown", and dividing by all of them would report a
     * confident 0% where the truth is "not measured yet".
     *
     * Learned addresses stay hidden — the owner did not enter them and cannot
     * act on them. Their own declared ones are returned, because they typed
     * those and must be able to see and remove them. `your_ip` is the address
     * this very request arrived from, which is what lets the dashboard offer
     * "use this connection" instead of asking an owner to go find their public
     * IP on a lookup site.
     *
     * @return array<string,mixed>
     */
    public function stats(Branch $branch, ?string $requestIp = null): array
    {
        $days = (int) config('platform.presence.egress_learning_days', 30);

        $window = fn () => MenuSession::withoutGlobalScopes()
            ->where('branch_id', $branch->id)
            ->where('started_at', '>=', now()->subDays($days));

        $measured = $window()->whereNotNull('on_branch_network')->count();
        $onWifi = $window()->where('on_branch_network', true)->count();

        return [
            'window_days' => $days,
            // The fence is the prerequisite: with it off, no session is ever
            // verified, so there is nothing to learn an address from. Reflects
            // the platform switch as well as the branch's own setting, so the
            // dashboard never claims learning is running when it cannot be.
            'geofence_enabled' => config('platform.presence.geofence_enforcement', false)
                && (bool) $branch->geofence_enabled,
            // Whether learning is possible at all right now. False means
            // declaring the address by hand is the only route.
            'learning_active' => (bool) config('platform.presence.geofence_enforcement', false),
            'wifi_detected' => $this->knownAddresses($branch) !== [],
            // Owner-declared entries, so the dashboard can list and remove them.
            'manual_ips' => is_array($branch->egress_ips_manual) ? $branch->egress_ips_manual : [],
            // Whether anything was learned on its own, distinct from declared.
            'learned' => ! empty($branch->egress_ips),
            'learned_at' => $branch->egress_ips_learned_at,
            // The address this request came from — the "use this connection"
            // shortcut, meaningful when the owner opens the dashboard on the
            // venue's own Wi-Fi.
            'your_ip' => EgressIp::normalize($requestIp),
            // Has the line moved? Surfaces a replacement to confirm, and flags
            // declared addresses nothing has arrived from.
            'drift' => $this->drift($branch),
            'sessions' => $window()->count(),
            'measured_sessions' => $measured,
            'on_wifi_sessions' => $onWifi,
            'on_wifi_rate' => $measured > 0 ? (int) round($onWifi / $measured * 100) : null,
        ];
    }

    /**
     * Has this branch's connection changed address?
     *
     * Answers the question an owner would otherwise have to notice themselves.
     * A dynamic line rotates its public address every few hours or days, and a
     * declared address then matches nobody while the dashboard still cheerfully
     * reports "recognised" — failing silently, which is the worst way to fail.
     *
     * Unlike learning, this does not need the geofence: it reads where the
     * branch's own table scans came from. That is a weaker signal (a scan is
     * not proof of presence), which is exactly why the result is a *suggestion*
     * the owner confirms, never an automatic switch. Promoting whichever
     * address dominates would hand the branch to anyone willing to scan a
     * photographed QR often enough.
     *
     * @return array{suggested: array{ip: string, sessions: int, share: int}|null, stale: list<string>, window_days: int}
     */
    public function drift(Branch $branch): array
    {
        $days = (int) config('platform.presence.egress_learning_days', 30);
        $minSessions = (int) config('platform.presence.egress_drift_min_sessions', 5);
        $minShare = (int) config('platform.presence.egress_drift_min_share', 60);

        $rows = MenuSession::withoutGlobalScopes()
            ->where('branch_id', $branch->id)
            ->whereNotNull('client_ip')
            ->where('started_at', '>=', now()->subDays($days))
            ->groupBy('client_ip')
            ->selectRaw('client_ip, count(*) as sessions')
            ->pluck('sessions', 'client_ip');

        $tallies = [];
        foreach ($rows as $ip => $sessions) {
            $token = EgressIp::normalize((string) $ip);
            if ($token !== null) {
                $tallies[$token] = ($tallies[$token] ?? 0) + (int) $sessions;
            }
        }

        $total = array_sum($tallies);
        $known = $this->knownAddresses($branch);
        $declared = is_array($branch->egress_ips_manual) ? $branch->egress_ips_manual : [];

        // Declared addresses that no traffic has arrived from all window. The
        // owner can act on this even when no replacement is obvious yet.
        $stale = array_values(array_filter($declared, fn (string $ip) => ($tallies[$ip] ?? 0) === 0));

        arsort($tallies);
        $topIp = array_key_first($tallies);
        $suggested = null;

        // Only meaningful as *drift* once something is on file. With nothing
        // declared this is just the ordinary "add your connection" flow, and
        // guessing from traffic there would be a weaker path to the same place.
        if ($known !== [] && $topIp !== null && ! in_array($topIp, $known, true)) {
            $share = $total > 0 ? (int) round($tallies[$topIp] / $total * 100) : 0;

            if ($tallies[$topIp] >= $minSessions && $share >= $minShare) {
                $suggested = ['ip' => $topIp, 'sessions' => $tallies[$topIp], 'share' => $share];
            }
        }

        return ['suggested' => $suggested, 'stale' => $stale, 'window_days' => $days];
    }

    /**
     * Recompute a branch's egress IPs from its geofence-verified sessions.
     *
     * Only sessions the fence vouched for are counted, because they are the
     * only ones known to have been on the premises — learning from unverified
     * sessions would teach the branch whatever carrier IP happened to recur.
     * A minimum session count keeps one-off coincidences out, and the cap keeps
     * a branch from accumulating a long tail of near-miss addresses.
     *
     * @return list<string> the addresses now stored for the branch
     */
    public function learn(Branch $branch): array
    {
        $days = (int) config('platform.presence.egress_learning_days', 30);
        $minSessions = (int) config('platform.presence.egress_min_sessions', 5);
        $maxIps = (int) config('platform.presence.egress_max_ips', 5);

        // Counted in SQL first so a busy branch returns one row per distinct
        // address rather than one per session, then folded in PHP because the
        // IPv6 /64 normalisation has no portable SQL equivalent.
        $counts = MenuSession::withoutGlobalScopes()
            ->where('branch_id', $branch->id)
            ->where('presence_source', MenuSession::PRESENCE_GEOFENCE)
            ->whereNotNull('client_ip')
            ->where('started_at', '>=', now()->subDays($days))
            ->groupBy('client_ip')
            ->selectRaw('client_ip, count(*) as sessions')
            ->pluck('sessions', 'client_ip');

        $tallies = [];
        foreach ($counts as $ip => $sessions) {
            $token = EgressIp::normalize((string) $ip);
            if ($token !== null) {
                $tallies[$token] = ($tallies[$token] ?? 0) + (int) $sessions;
            }
        }

        $learned = collect($tallies)
            ->filter(fn (int $sessions) => $sessions >= $minSessions)
            ->sortDesc()
            ->take($maxIps)
            ->keys()
            ->all();

        // forceFill: these columns are intentionally not fillable, so nothing
        // reachable from a request can write them.
        $branch->forceFill([
            'egress_ips' => $learned === [] ? null : $learned,
            'egress_ips_learned_at' => now(),
        ])->save();

        return $learned;
    }
}
