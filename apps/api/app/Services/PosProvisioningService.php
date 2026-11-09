<?php

namespace App\Services;

use App\Exceptions\PosApiException;
use App\Models\Branch;
use App\Models\Order;
use App\Models\Plan;
use App\Models\PosLicence;
use App\Models\PosPairingCode;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\TenderType;
use App\Models\User;
use App\Support\DeviceToken;
use App\Support\PairingCode;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * POS-BE-023: the platform provisions the terminal, the till claims it.
 *
 * Path A — dashboard creates the row (state `provisioned`), issues a pairing
 * code, the desktop claims it and receives the device credential + the full
 * bootstrap bundle. Path B — an authenticated staff account holding
 * pos.provision registers a terminal directly (installer with no dashboard
 * access).
 *
 * Idempotency: a claim that times out and retries with the same code from the
 * same device returns the byte-identical cached response, device token
 * included — never a second terminal (the cache is encrypted at rest and dies
 * with the code's TTL). Path B dedupes on client_transaction_id the same way.
 */
class PosProvisioningService
{
    public function __construct(private readonly PosBootstrapService $bootstrap) {}

    /**
     * Create a terminal for an EXISTING tenant. This is the only path that
     * mints a `provisioned` row, and it is never reached as a side effect of
     * anything — tenant creation does not call it, licence issuance does not
     * call it, and a tenant with zero terminals is a valid resting state.
     *
     * The tenant is passed explicitly rather than read off the actor, because
     * both front doors need it: the restaurant's own dashboard (actor's own
     * tenant) and the Super Admin's tenant page (an actor with no tenant of
     * their own, acting on one by id).
     */
    public function provision(Restaurant $restaurant, User $actor, array $data): PosTerminal
    {
        // Scoped find for a tenant actor; for a Super Admin the scope is a
        // no-op, so the ownership check below is what actually holds the line.
        // A foreign branch id resolves to a 404 either way — the
        // no-existence-leak posture.
        $branch = Branch::find($data['branch_id']);

        if ($branch === null || $branch->restaurant_id !== $restaurant->id) {
            abort(404, __('xorder.messages.branch_not_found'));
        }

        // A terminal ROW spends a seat, claimed or not (owner decision,
        // 2026-09-05): a two-seat plan holds two terminals. Inside the
        // transaction and behind a lock so two operators creating the last
        // seat at once cannot both be let through.
        return DB::transaction(function () use ($restaurant, $actor, $branch, $data) {
            // Lock the tenant row, not a terminal row: the thing being counted
            // does not exist yet, so there is nothing else to serialise two
            // operators creating the last seat at the same moment against.
            Restaurant::whereKey($restaurant->id)->lockForUpdate()->first();

            $this->assertSeatAvailable($restaurant, 'occupied');

            $terminal = new PosTerminal([
                'name' => $data['name'],
                'deployment_mode' => $data['deployment_mode'] ?? 'cloud',
                'sync_policy' => $data['sync_policy'] ?? 'dynamic',
            ]);
            $terminal->forceFill([
                'restaurant_id' => $restaurant->id,
                'branch_id' => $branch->id,
                'terminal_id' => (string) Str::uuid(),
                'state' => PosTerminal::STATE_PROVISIONED,
            ])->save();

            $this->ensureDefaultTenders($restaurant);

            AuditLogger::record('pos_terminal.provisioned', [
                'restaurant_id' => $restaurant->id,
                'actor' => $actor,
                'auditable' => $terminal,
                'description' => sprintf('POS terminal "%s" provisioned for branch #%d', $terminal->name, $branch->id),
            ]);

            return $terminal;
        });
    }

    /**
     * Issue (or regenerate) the pairing code. Regenerating expires every
     * earlier unused code — exactly one live code per terminal, so "read it
     * off the dashboard again" always reads the one that works.
     *
     * @return string the plaintext code — shown once, stored only as HMAC
     */
    public function issuePairingCode(PosTerminal $terminal, User $actor): string
    {
        $code = PairingCode::generate();

        DB::transaction(function () use ($terminal, $actor, $code) {
            $terminal->pairingCodes()
                ->whereNull('used_at')
                ->update(['expires_at' => now()->subSecond(), 'response_cache' => null]);

            (new PosPairingCode)->forceFill([
                'restaurant_id' => $terminal->restaurant_id,
                'pos_terminal_id' => $terminal->id,
                'code_hash' => PairingCode::hash($code),
                'expires_at' => now()->addHours(PairingCode::TTL_HOURS),
                'created_by_id' => $actor->id,
            ])->save();
        });

        AuditLogger::record('pos_terminal.pairing_code_issued', [
            'restaurant_id' => $terminal->restaurant_id,
            'auditable' => $terminal,
            'description' => sprintf('Pairing code issued for terminal "%s"', $terminal->name),
        ]);

        return $code;
    }

    /**
     * Path A. Unauthenticated — the code is the credential. The tenant is
     * resolved FROM the code's own row (the slug only disambiguates), and a
     * wrong slug or unknown code fail identically so nothing is enumerable.
     *
     * @return array{body: array, replay: bool}
     */
    public function claim(array $data): array
    {
        $restaurant = Restaurant::where('slug', $data['tenant_slug'])->first();

        if ($restaurant === null) {
            throw new PosApiException('PAIRING_CODE_INVALID', 422);
        }

        $row = PosPairingCode::withoutGlobalScopes()
            ->where('restaurant_id', $restaurant->id)
            ->where('code_hash', PairingCode::hash($data['pairing_code']))
            ->latest('id')
            ->first();

        if ($row === null) {
            throw new PosApiException('PAIRING_CODE_INVALID', 422);
        }

        $fingerprint = $data['fingerprint'] ?? null;

        if ($row->used_at !== null) {
            // Same device replaying a timed-out claim inside the TTL: return
            // the identical cached response. Anyone else: the honest "this
            // code was already used", never a second terminal.
            if ($row->response_cache !== null
                && ! $row->isExpired()
                && $fingerprint !== null
                && $row->used_fingerprint === $fingerprint) {
                return ['body' => json_decode(Crypt::decryptString($row->response_cache), true), 'replay' => true];
            }

            throw new PosApiException('PAIRING_CODE_USED', 422);
        }

        if ($row->isExpired()) {
            $row->forceFill(['response_cache' => null])->save();

            throw new PosApiException('PAIRING_CODE_EXPIRED', 422);
        }

        TenantContext::overrideId($restaurant->id);

        try {
            $body = DB::transaction(function () use ($row, $restaurant, $data, $fingerprint) {
                $terminal = $row->terminal()->lockForUpdate()->first();

                if ($terminal === null || $terminal->isRevoked()) {
                    throw new PosApiException('PAIRING_CODE_INVALID', 422);
                }

                // A terminal already active is re-claiming its own seat and
                // must not be counted against itself; anything else is a NEW
                // device and needs a free seat. Inside the transaction and
                // after the row lock, so two devices racing the last seat
                // cannot both be let through.
                if (! $terminal->isActive()) {
                    $this->assertSeatAvailable($restaurant);
                }

                // Backstop for a terminal provisioned before the defaults
                // existed: its first bundle is built right below.
                $this->ensureDefaultTenders($restaurant);

                $token = DeviceToken::generate();

                $terminal->forceFill([
                    'state' => PosTerminal::STATE_ACTIVE,
                    'claimed_at' => now(),
                    'platform' => $data['platform'] ?? null,
                    'app_version' => $data['app_version'] ?? null,
                    'fingerprint' => $fingerprint,
                    'device_token_hash' => DeviceToken::hash($token),
                ])->save();

                $body = [
                    'device_token' => $token,
                    'terminal' => $this->terminalBlock($terminal),
                    'warnings' => $this->seatWarnings($restaurant),
                    'server_time' => now()->toIso8601String(),
                    'bootstrap' => $this->bootstrap->bundle($terminal),
                ];

                $row->forceFill([
                    'used_at' => now(),
                    'used_fingerprint' => $fingerprint,
                    'response_cache' => Crypt::encryptString(json_encode($body)),
                ])->save();

                return $body;
            });
        } finally {
            TenantContext::clearOverride();
        }

        AuditLogger::record('pos_terminal.claimed', [
            'restaurant_id' => $restaurant->id,
            'actor_role' => 'TERMINAL',
            'description' => sprintf('POS terminal "%s" claimed', $body['terminal']['name']),
            'properties' => ['terminal_id' => $body['terminal']['id'], 'fingerprint' => $fingerprint],
        ]);

        return ['body' => $body, 'replay' => false];
    }

    /**
     * Path B — authenticated self-registration, idempotent on the client's
     * transaction id (the cached response, device token included, is returned
     * on replay).
     *
     * @return array{body: array, replay: bool}
     */
    public function register(User $actor, array $data): array
    {
        $existing = PosTerminal::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->register_response_cache === null) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['body' => json_decode(Crypt::decryptString($existing->register_response_cache), true), 'replay' => true];
        }

        $branch = Branch::find($data['branch_id']);

        if ($branch === null) {
            throw new PosApiException('BRANCH_NOT_IN_TENANT', 404);
        }

        $body = DB::transaction(function () use ($actor, $branch, $data) {
            // Path B creates a brand-new terminal AND claims it in one step,
            // so it spends an occupied seat — the same count the dashboard
            // spends. Checking only `claimed` here would be the hole that
            // makes the creation cap meaningless: fill every seat with
            // provisioned rows, then self-register past them.
            $this->assertSeatAvailable($actor->restaurant, 'occupied');

            $token = DeviceToken::generate();

            $terminal = new PosTerminal([
                'name' => $data['name'],
                'deployment_mode' => $data['deployment_mode'] ?? 'cloud',
                'sync_policy' => $data['sync_policy'] ?? 'dynamic',
            ]);
            $terminal->forceFill([
                'restaurant_id' => $actor->restaurant_id,
                'branch_id' => $branch->id,
                'terminal_id' => (string) Str::uuid(),
                'state' => PosTerminal::STATE_ACTIVE,
                'claimed_at' => now(),
                'platform' => $data['platform'] ?? null,
                'app_version' => $data['app_version'] ?? null,
                'fingerprint' => $data['fingerprint'] ?? null,
                'device_token_hash' => DeviceToken::hash($token),
                'client_transaction_id' => $data['client_transaction_id'],
            ])->save();

            $this->ensureDefaultTenders($actor->restaurant);

            $body = [
                'device_token' => $token,
                'terminal' => $this->terminalBlock($terminal),
                'warnings' => $this->seatWarnings($actor->restaurant),
                'server_time' => now()->toIso8601String(),
                'bootstrap' => $this->bootstrap->bundle($terminal),
            ];

            $terminal->forceFill(['register_response_cache' => Crypt::encryptString(json_encode($body))])->save();

            return $body;
        });

        AuditLogger::record('pos_terminal.registered', [
            'restaurant_id' => $actor->restaurant_id,
            'description' => sprintf('POS terminal "%s" self-registered (Path B)', $data['name']),
            'properties' => ['terminal_id' => $body['terminal']['id']],
        ]);

        return ['body' => $body, 'replay' => false];
    }

    /**
     * Rotate the device credential. The OLD token stays valid for 24h
     * (PosDeviceAuth honours previous_token_hash) so a crash between receiving
     * and persisting the new one cannot brick the till.
     */
    public function rotateToken(PosTerminal $terminal): string
    {
        $token = DeviceToken::generate();

        $terminal->forceFill([
            'previous_token_hash' => $terminal->device_token_hash,
            'device_token_hash' => DeviceToken::hash($token),
            'device_token_rotated_at' => now(),
        ])->save();

        AuditLogger::record('pos_terminal.token_rotated', [
            'restaurant_id' => $terminal->restaurant_id,
            'auditable' => $terminal,
            'actor_role' => 'TERMINAL',
            'description' => sprintf('Device token rotated for terminal "%s"', $terminal->name),
        ]);

        return $token;
    }

    /** BE-A04: stops future trade, never erases past trade. */
    public function revoke(PosTerminal $terminal, User $actor): void
    {
        $terminal->forceFill([
            'state' => PosTerminal::STATE_REVOKED,
            'revoked_at' => now(),
        ])->save();

        AuditLogger::record('pos_terminal.revoked', [
            'restaurant_id' => $terminal->restaurant_id,
            'auditable' => $terminal,
            'description' => sprintf('POS terminal "%s" revoked', $terminal->name),
        ]);
    }

    /**
     * Delete a terminal record outright — owner decision, 2026-09-05, the same
     * split as licences: revoke stops trade, delete is cleanup.
     *
     * Two guards, both load-bearing. It must be REVOKED first, because an
     * active terminal holds a live device token and deleting the row would
     * strand a till mid-service with a credential the server no longer knows.
     * And it must have NO MONEY HISTORY: pos_shifts cascade on terminal delete
     * and orders lose their attribution, so a till that ever traded is a
     * record, not clutter, and it stays. What this removes is the
     * never-claimed, never-used leftover — including one whose only trace is
     * an empty shift somebody opened while testing the pairing, which is
     * clutter of exactly the same kind and used to pin the row forever.
     *
     * Lives here rather than in a controller because both front doors — the
     * restaurant's dashboard and the Super Admin's tenant page — must apply
     * exactly these rules. A second copy is a second set of guards to get
     * wrong, and money history is not a thing to be wrong about.
     */
    public function delete(PosTerminal $terminal, User $actor): void
    {
        if (! $terminal->isRevoked()) {
            throw new PosApiException('TERMINAL_STILL_ACTIVE', 422, null, __('xorder.errors.pos_terminal_still_active'));
        }

        // A shift ROW is not money history. A till paired for a test, with a
        // shift opened on it and nothing else — no order, nothing in the
        // drawer, never closed — leaves the same leftover the terminal row is,
        // and cascades with it. What must survive is anything that TRADED: an
        // order, a float, a counted drawer, a close.
        $tradedShift = PosShift::query()->withoutGlobalScopes()
            ->where('pos_terminal_id', $terminal->id)
            ->where(fn ($shift) => $this->shiftTraded($shift))
            ->exists();

        $hasHistory = $tradedShift
            || Order::query()->withoutGlobalScopes()
                ->where('pos_terminal_id', $terminal->id)->exists();

        if ($hasHistory) {
            throw new PosApiException('TERMINAL_HAS_HISTORY', 422, null, __('xorder.errors.pos_terminal_has_history'));
        }

        AuditLogger::record('pos_terminal.deleted', [
            'actor' => $actor,
            'restaurant_id' => $terminal->restaurant_id,
            'description' => sprintf('POS terminal "%s" deleted (never traded)', $terminal->name),
            'properties' => ['terminal_id' => $terminal->terminal_id, 'name' => $terminal->name],
        ]);

        $terminal->delete();
    }

    /**
     * Add `has_money_history` to a terminal list query: true exactly when
     * delete() would answer TERMINAL_HAS_HISTORY. XORD-042 — the dashboards
     * offered Delete on every revoked terminal and learned the answer only
     * after the owner confirmed.
     *
     * One EXISTS per kind of history inside the list query, so a page of
     * terminals costs one query, not one per row. Global scopes are off for
     * the same reason as in delete(): the terminal's own rows are the
     * question, whoever is asking (the Super Admin has no tenant context).
     *
     * It sets the select list (`pos_terminals.*` plus the flag): call it
     * before adding columns of your own, or they are replaced.
     */
    public function withMoneyHistory(Builder $query): Builder
    {
        $tradedShift = PosShift::query()->withoutGlobalScopes()
            ->selectRaw('1')
            ->whereColumn('pos_shifts.pos_terminal_id', 'pos_terminals.id')
            ->where(fn ($shift) => $this->shiftTraded($shift));

        $order = Order::query()->withoutGlobalScopes()
            ->selectRaw('1')
            ->whereColumn('orders.pos_terminal_id', 'pos_terminals.id');

        return $query
            ->select('pos_terminals.*')
            ->selectRaw(
                '(exists ('.$tradedShift->toSql().') or exists ('.$order->toSql().')) as has_money_history',
                [...$tradedShift->getBindings(), ...$order->getBindings()],
            );
    }

    /** A shift that moved money: a float, a count or a close. See delete(). */
    private function shiftTraded($shift): void
    {
        $shift->whereNotNull('closed_at')
            ->orWhereNotNull('closed_by_id')
            ->orWhereNotNull('counted_cash_minor')
            ->orWhere('opening_float_minor', '>', 0);
    }

    /**
     * POS-BE-022: absorb a heartbeat (last write wins, no history) and answer
     * with the five agreed fields — one response serving clock skew, the
     * offline window, the renewal banner, config-change detection and
     * revocation discovery.
     */
    public function heartbeat(PosTerminal $terminal, array $data): array
    {
        $terminal->forceFill([
            'last_seen_at' => now(),
            'app_version' => $data['app_version'] ?? $terminal->app_version,
            'platform' => $data['platform'] ?? $terminal->platform,
            'pending_count' => $data['pending_count'] ?? null,
            'oldest_pending_at' => $data['oldest_pending_at'] ?? null,
            'shift_open' => $data['shift_open'] ?? null,
            'clock_offset_seconds' => $data['clock_offset_seconds'] ?? null,
            'last_catalog_sync_at' => $data['last_catalog_sync_at'] ?? null,
            'reported_licence_expires_at' => $data['licence_expires_at'] ?? null,
        ])->saveQuietly(); // a heartbeat is telemetry, not an audited edit

        $licence = PosLicence::query()
            ->where('restaurant_id', $terminal->restaurant_id)
            ->live()
            ->latest('id')
            ->first();

        return [
            'server_time' => now()->toIso8601String(),
            // Site tier is POS-BE-026 (deferred); null = no site, which is the
            // truthful cloud answer.
            'site_last_contact_at' => null,
            'licence_expires_at' => $licence?->expires_at?->toIso8601String(),
            'config_version' => PosConfigVersion::current($terminal->restaurant_id),
            'terminal_status' => $terminal->isRevoked() ? 'revoked' : 'active',
        ];
    }

    /**
     * Seats bought, and seats spent — two different counts, on purpose.
     *
     * `claimed` is tills actually PAIRED. `occupied` also counts provisioned
     * rows waiting for a device. The plan limit is enforced against `occupied`
     * (owner decision, 2026-09-05): a two-seat plan may hold two terminal rows
     * in total, so the number an operator sees on the dashboard is the number
     * they can create. Counting only claimed rows would let a two-seat client
     * build a list of ten tills and discover the limit one device at a time,
     * at the counter, which is the worst possible place to learn it.
     *
     * `claimed` survives because pairing still checks it: it is the backstop
     * for a plan that SHRANK under tills that already exist, where the rows are
     * already there and only a new pairing can be refused.
     *
     * A revoked row spends nothing either way — revoking frees the seat for
     * both counts immediately.
     *
     * Licence cap wins over plan cap when both exist: the licence is the
     * record of what was actually sold, and a bespoke deal is not a plan tier.
     *
     * @return array{max: int|null, claimed: int, occupied: int}
     */
    private function seats(Restaurant $restaurant): array
    {
        $licenceMax = PosLicence::query()
            ->where('restaurant_id', $restaurant->id)
            ->live()->latest('id')->value('max_terminals');

        $planMax = $restaurant->subscription_plan
            ? Plan::where('name', $restaurant->subscription_plan)->value('max_terminals')
            : null;

        // One pass, two numbers. CASE rather than the FILTER clause: this same
        // query runs on SQLite in the test suite and Postgres in production.
        $counts = PosTerminal::withoutGlobalScopes()
            ->where('restaurant_id', $restaurant->id)
            ->where('state', '!=', PosTerminal::STATE_REVOKED)
            ->selectRaw('count(*) as occupied')
            ->selectRaw('sum(case when state = ? then 1 else 0 end) as claimed', [PosTerminal::STATE_ACTIVE])
            ->first();

        return [
            'max' => $licenceMax ?? $planMax,
            'claimed' => (int) $counts->claimed,
            'occupied' => (int) $counts->occupied,
        ];
    }

    /**
     * Refuse when every seat is spent (owner decision, 2026-09-05, overruling
     * POS-BE-016's warn-only rule; extended to creation 2026-09-05).
     *
     * Called at two moments with two different counts. CREATION checks
     * `occupied`, so a two-seat plan holds two terminal rows and no more —
     * the limit is discovered in the dashboard, by the person who can act on
     * it, instead of at the counter by whoever is holding the device. PAIRING
     * checks `claimed`, which now only bites when a plan shrank under rows
     * that already exist.
     *
     * The "never brick a till" principle survives intact, because it protects
     * a till that is ALREADY TRADING — mid-shift, cash in the drawer. Neither
     * moment is that: nobody is at the counter and no money is at risk.
     * Nothing downstream — bootstrap, orders, shifts, cash-up, reprint, export
     * — ever consults this.
     *
     * @param  'occupied'|'claimed'  $against  which count this moment spends
     */
    private function assertSeatAvailable(Restaurant $restaurant, string $against = 'claimed'): void
    {
        $seats = $this->seats($restaurant);
        $max = $seats['max'];
        $spent = $seats[$against];

        if ($max === null || $spent < $max) {
            return;
        }

        // The numbers are passed explicitly rather than left to the code-name
        // fallback, so both the dashboard and the till can show the actual
        // counts to whoever hit the wall.
        throw new PosApiException(
            'TERMINAL_SEAT_LIMIT',
            422,
            ['seats' => ['max' => (int) $max, 'claimed' => $seats['claimed'], 'occupied' => $seats['occupied']]],
            __('xorder.errors.pos_seat_limit', ['max' => $max, 'claimed' => $spent]),
        );
    }

    /**
     * POS-BE-016 warnings, kept for the over-limit case that predates
     * enforcement: a restaurant whose plan SHRANK below the tills it already
     * has is over its count without any new device claiming, and must be told
     * rather than cut off.
     *
     * @return list<array{code: string, details: array<string,int>}>
     */
    private function seatWarnings(Restaurant $restaurant): array
    {
        ['max' => $max, 'claimed' => $claimed] = $this->seats($restaurant);

        if ($max === null || $claimed <= $max) {
            return [];
        }

        return [[
            'code' => 'MAX_TERMINALS_EXCEEDED',
            'details' => ['licensed' => (int) $max, 'claimed' => $claimed],
        ]];
    }

    /**
     * A POS restaurant never delivers an empty money.tender_types (defect fix,
     * owner go 2026-09-11; POS-BE-013 amendment in BACKEND_TO_POS.md).
     *
     * Why: a payment's tender_type_id must be an id from the bundle, and
     * nothing but the dashboard's TenderTypeController::store ever made one.
     * A restaurant that paired a till before authoring tenders got an empty
     * list, and a cloud till then had no valid way to take money. Null is not
     * a way out, because the shift report counts an untyped payment as cash.
     *
     * Why HERE, at terminal birth: every path to a first bundle goes through
     * provision() (Path A, both front doors, then claim) or register()
     * (Path B). Both are already writes, inside a transaction, so the tender
     * rows commit with the terminal or not at all. The earlier candidates
     * don't work. Tenant creation seeds non-POS restaurants too. Enabling the
     * pos feature is spread across plan sync and admin toggles, with no single
     * hook. The bundle is a GET, and a GET should not write. claim() calls
     * this as well, as a backstop for a terminal provisioned before this
     * existed.
     *
     * Idempotent: seeds ONLY when the restaurant has zero tender types,
     * inactive ones included. An owner who deactivated every tender chose
     * that; a second terminal adds nothing. Scoped by hand
     * (withoutGlobalScopes + explicit restaurant_id), because on the Super
     * Admin front door the RestaurantScope is a no-op and a scoped count would
     * see every tenant's tenders.
     *
     * Matches the dashboard store path exactly: plain model saves, so the
     * Auditable trait records tender_type.created and the PosConfigVersion
     * hook bumps pos_config_version. Neither is called by hand. Single-column
     * names (no name_ar), written in the restaurant's default language.
     */
    private function ensureDefaultTenders(Restaurant $restaurant): void
    {
        $has = fn () => TenderType::withoutGlobalScopes()
            ->where('restaurant_id', $restaurant->id)
            ->exists();

        if ($has()) {
            return;
        }

        // Two first-terminals at once must not both see zero. Lock the tenant
        // row (the rows being counted don't exist yet) and check again.
        Restaurant::whereKey($restaurant->id)->lockForUpdate()->first();

        if ($has()) {
            return;
        }

        $locale = $restaurant->default_language?->value ?? 'en';

        foreach (['cash', 'card'] as $sort => $kind) {
            $tender = new TenderType([
                'name' => __('xorder.pos.default_tender_'.$kind, [], $locale),
                'kind' => $kind,
                'is_active' => true,
                'sort_order' => $sort,
            ]);
            $tender->forceFill(['restaurant_id' => $restaurant->id])->save();
        }
    }

    /** @return array<string,mixed> */
    public function terminalBlock(PosTerminal $terminal): array
    {
        return [
            'id' => $terminal->terminal_id,
            'name' => $terminal->name,
            'branch_id' => $terminal->branch_id,
            'deployment_mode' => $terminal->deployment_mode,
            'sync_policy' => $terminal->sync_policy,
            'state' => $terminal->state,
        ];
    }
}
