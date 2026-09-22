<?php

namespace App\Services;

use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Exceptions\PosApiException;
use App\Models\Branch;
use App\Models\OrderPayment;
use App\Models\PosCashMovement;
use App\Models\PosRefund;
use App\Models\PosRefundTender;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * POS-BE-009: shifts and cash movements. One open shift per terminal,
 * enforced under a lock on the terminal row; every write idempotent per
 * POS-BE-007; client times stored as sent.
 *
 * Expected cash is A3, confirmed:
 *   opening_float + cash_sales + cash_in − cash_out − cash_refunds
 * (cash_refunds became real when POS-BE-010 landed — money handed back in cash
 * is not in the drawer, and a Z report that ignored it would show every
 * refunding till as short. A future payouts concept arrives as a cash-movement
 * reason, never a new term.)
 */
class PosShiftService
{
    /** @return array{shift: PosShift, replay: bool} */
    public function open(PosTerminal $terminal, array $data): array
    {
        $hash = $this->hash([$data['client_transaction_id'], (int) $data['opening_float_minor'], $data['opened_at']]);

        $existing = PosShift::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->payload_hash !== $hash) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['shift' => $existing, 'replay' => true];
        }

        $branch = Branch::find($data['branch_id']);

        if ($branch === null) {
            throw new PosApiException('BRANCH_NOT_IN_TENANT', 404);
        }

        $actor = $this->actor($terminal, $data['acting_user_id'] ?? null, TenantCapability::POS_SHIFT_OPEN);

        $shift = DB::transaction(function () use ($terminal, $branch, $data, $actor, $hash) {
            // The terminal row is the mutex for "one open shift per terminal":
            // two concurrent opens serialise here, and the second sees the
            // first's row.
            PosTerminal::withoutGlobalScopes()->whereKey($terminal->id)->lockForUpdate()->first();

            $open = PosShift::where('pos_terminal_id', $terminal->id)
                ->where('status', PosShift::STATUS_OPEN)
                ->exists();

            if ($open) {
                throw new PosApiException('SHIFT_ALREADY_OPEN', 422);
            }

            $shift = (new PosShift)->forceFill([
                'restaurant_id' => $terminal->restaurant_id,
                'branch_id' => $branch->id,
                'pos_terminal_id' => $terminal->id,
                'client_transaction_id' => $data['client_transaction_id'],
                'opened_by_id' => $actor?->id,
                // Normalised to app tz — see PosOrderService on why raw
                // offsets silently shift on read-back.
                'opened_at' => Carbon::parse($data['opened_at'])->setTimezone(config('app.timezone')),
                'received_at' => now(),
                'opening_float_minor' => (int) $data['opening_float_minor'],
                'status' => PosShift::STATUS_OPEN,
                'payload_hash' => $hash,
            ]);
            $shift->save();

            return $shift;
        });

        return ['shift' => $shift, 'replay' => false];
    }

    /** @return array{shift: PosShift, replay: bool} */
    public function close(PosTerminal $terminal, string $ref, array $data): array
    {
        $shift = $this->resolve($terminal, $ref);
        $hash = $this->hash([$data['client_transaction_id'], (int) $data['counted_cash_minor'], $data['closed_at']]);

        if (! $shift->isOpen()) {
            if ($shift->close_payload_hash === $hash) {
                return ['shift' => $shift, 'replay' => true];
            }

            throw new PosApiException('SHIFT_NOT_OPEN', 422);
        }

        $actor = $this->actor($terminal, $data['acting_user_id'] ?? null, TenantCapability::POS_SHIFT_CLOSE);

        $expected = $this->expectedCash($shift);
        $counted = (int) $data['counted_cash_minor'];
        $variance = $counted - $expected;

        if ($variance !== 0 && empty($data['variance_reason'])) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['variance_reason' => ['Required when counted cash differs from expected ('.$variance.').']],
            ]);
        }

        $shift->forceFill([
            'closed_by_id' => $actor?->id,
            'closed_at' => Carbon::parse($data['closed_at'])->setTimezone(config('app.timezone')),
            'counted_cash_minor' => $counted,
            'expected_cash_minor' => $expected,
            'variance_minor' => $variance,
            'variance_reason' => $data['variance_reason'] ?? null,
            'denominations' => $data['denominations'] ?? null,
            'status' => PosShift::STATUS_CLOSED,
            'close_payload_hash' => $hash,
        ])->save();

        AuditLogger::record('pos_shift.closed', [
            'restaurant_id' => $shift->restaurant_id,
            'actor' => $actor,
            'actor_role' => $actor === null ? 'TERMINAL' : null,
            'auditable' => $shift,
            'description' => sprintf('Shift closed with variance %d', $variance),
            'properties' => [
                'expected_cash_minor' => $expected,
                'counted_cash_minor' => $counted,
                'variance_minor' => $variance,
            ],
        ]);

        return ['shift' => $shift, 'replay' => false];
    }

    public function current(PosTerminal $terminal): ?PosShift
    {
        return PosShift::where('pos_terminal_id', $terminal->id)
            ->where('status', PosShift::STATUS_OPEN)
            ->latest('id')
            ->first();
    }

    /** @return array{movement: PosCashMovement, replay: bool} */
    public function cashMovement(PosTerminal $terminal, array $data): array
    {
        $hash = $this->hash([
            $data['client_transaction_id'], $data['direction'],
            (int) $data['amount_minor'], $data['reason'],
        ]);

        $existing = PosCashMovement::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->payload_hash !== $hash) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['movement' => $existing, 'replay' => true];
        }

        $shift = PosShift::where('pos_terminal_id', $terminal->id)
            ->where('client_transaction_id', $data['shift_client_id'])
            ->where('status', PosShift::STATUS_OPEN)
            ->first();

        if ($shift === null) {
            throw new PosApiException('SHIFT_NOT_OPEN', 422);
        }

        $actor = $this->actor($terminal, $data['acting_user_id'] ?? null, TenantCapability::POS_CASH_MOVEMENT);

        $movement = (new PosCashMovement)->forceFill([
            'restaurant_id' => $terminal->restaurant_id,
            'branch_id' => $shift->branch_id,
            'pos_shift_id' => $shift->id,
            'pos_terminal_id' => $terminal->id,
            'client_transaction_id' => $data['client_transaction_id'],
            'acting_user_id' => $actor?->id,
            'direction' => $data['direction'],
            'amount_minor' => (int) $data['amount_minor'],
            'reason' => $data['reason'],
            'reference' => $data['reference'] ?? null,
            'occurred_at' => Carbon::parse($data['occurred_at'])->setTimezone(config('app.timezone')),
            'received_at' => now(),
            'payload_hash' => $hash,
        ]);
        $movement->save();

        return ['movement' => $movement, 'replay' => false];
    }

    /**
     * X/Z figures. Branch-scoped to the REQUESTING terminal (BE-A02's ask): a
     * cashier pressing the report key must not read another branch's cash
     * position, whatever their capability would allow — cross-branch reporting
     * is a dashboard feature.
     */
    public function report(PosTerminal $terminal, string $ref): array
    {
        $shift = $this->resolve($terminal, $ref);

        $byTender = OrderPayment::where('pos_shift_id', $shift->id)
            ->selectRaw('tender_type_id, SUM(amount_minor) as amount, COUNT(*) as payments')
            ->groupBy('tender_type_id')
            ->get();

        $tenderNames = TenderType::whereIn('id', $byTender->pluck('tender_type_id')->filter())
            ->get()->keyBy('id');

        $movements = PosCashMovement::where('pos_shift_id', $shift->id)->get();

        return [
            'shift' => $shift,
            'orders_count' => $shift->orders()->count(),
            'sales_by_tender' => $byTender->map(fn ($row) => [
                'tender_type_id' => $row->tender_type_id,
                'name' => $tenderNames->get($row->tender_type_id)?->name,
                'kind' => $tenderNames->get($row->tender_type_id)?->kind,
                'amount_minor' => (int) $row->amount,
                'payments' => (int) $row->payments,
            ])->values()->all(),
            'cash_in_minor' => (int) $movements->where('direction', 'in')->sum('amount_minor'),
            'cash_out_minor' => (int) $movements->where('direction', 'out')->sum('amount_minor'),
            // POS-BE-010, additive keys: what went back in this shift, and how
            // much of it left the drawer. Both 0 on a shift with no refunds,
            // which is every shift the shipped contract described.
            'refunds_minor' => $this->refundsTotal($shift),
            'refunds_count' => PosRefund::where('pos_shift_id', $shift->id)->count(),
            'cash_refunds_minor' => $this->cashRefunds($shift, TenderType::where('kind', 'cash')->pluck('id')->all()),
            'expected_cash_minor' => $shift->isOpen() ? $this->expectedCash($shift) : $shift->expected_cash_minor,
            'server_time' => now()->toIso8601String(),
        ];
    }

    /**
     * A3: opening_float + cash_sales + cash_in − cash_out − cash_refunds.
     * Cash sales = payments in this shift whose tender kind is `cash`; a
     * payment with no tender type recorded is conservatively counted as cash
     * (an untyped drawer payment that is NOT in the drawer would hide a short).
     */
    public function expectedCash(PosShift $shift): int
    {
        $cashTenderIds = TenderType::where('kind', 'cash')->pluck('id');

        $cashSales = (int) OrderPayment::where('pos_shift_id', $shift->id)
            ->where(fn ($q) => $q->whereIn('tender_type_id', $cashTenderIds)->orWhereNull('tender_type_id'))
            ->sum('amount_minor');

        $movements = PosCashMovement::where('pos_shift_id', $shift->id)->get();

        return $shift->opening_float_minor
            + $cashSales
            + (int) $movements->where('direction', 'in')->sum('amount_minor')
            - (int) $movements->where('direction', 'out')->sum('amount_minor')
            - $this->cashRefunds($shift, $cashTenderIds->all());
    }

    /**
     * Cash handed back in this shift (POS-BE-010). Attributed to the shift the
     * REFUND belongs to, never the original sale's — the drawer that paid it
     * out is the drawer that is short.
     *
     * An untyped refund tender is counted as cash for the same conservative
     * reason an untyped payment is: a give-back that did not actually leave the
     * drawer would hide an overage, and hiding a discrepancy is the one
     * outcome a cash-up must never produce.
     *
     * @param  list<int>  $cashTenderIds
     */
    private function cashRefunds(PosShift $shift, array $cashTenderIds): int
    {
        return (int) PosRefundTender::query()
            ->whereIn('pos_refund_id', PosRefund::where('pos_shift_id', $shift->id)->select('id'))
            ->where(fn ($q) => $q->whereIn('tender_type_id', $cashTenderIds)->orWhereNull('tender_type_id'))
            ->sum('amount_minor');
    }

    /** Every refund raised in this shift, cash or not — the Z report's own line. */
    public function refundsTotal(PosShift $shift): int
    {
        return (int) PosRefund::where('pos_shift_id', $shift->id)->sum('total_minor');
    }

    /**
     * {id} accepts the server id or the shift's client uuid — an offline-
     * opened shift has no server id at close time. Terminal-branch scoped;
     * anything else is 404-shaped (SHIFT_NOT_OPEN would lie).
     */
    public function resolve(PosTerminal $terminal, string $ref): PosShift
    {
        $query = PosShift::where('branch_id', $terminal->branch_id);

        $shift = preg_match('/^\d+$/', $ref) === 1
            ? $query->find((int) $ref)
            : $query->where('client_transaction_id', $ref)->first();

        if ($shift === null) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['shift' => ['Unknown shift.']],
            ]);
        }

        return $shift;
    }

    private function actor(PosTerminal $terminal, ?int $userId, TenantCapability $required): ?User
    {
        if ($userId === null) {
            return null; // v1 relaxation — terminal-only attribution
        }

        $user = User::where('restaurant_id', $terminal->restaurant_id)
            ->where('status', UserStatus::ACTIVE)
            ->find($userId);

        if ($user === null || ! $user->isTenantUser()) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['acting_user_id' => ['Unknown user.']],
            ]);
        }

        if (! $user->holdsTenantCapability($required)) {
            throw new PosApiException('POS_CAPABILITY_MISSING', 403, ['capability' => $required->value]);
        }

        return $user;
    }

    private function hash(array $parts): string
    {
        return hash('sha256', json_encode($parts));
    }
}
