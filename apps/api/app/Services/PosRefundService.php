<?php

namespace App\Services;

use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Exceptions\PosApiException;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\PosRefund;
use App\Models\PosRefundLine;
use App\Models\PosRefundTender;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * POS-BE-010 — refunds as reversing records.
 *
 * Four things this service is, each of which was a decision:
 *
 * 1. **It never mutates the original.** No column on `orders` or `order_items`
 *    changes except the two counters (`refunded_minor`, `refunded_quantity`),
 *    and `orders.status` never moves at all — the OrderStatus invariant stays
 *    exactly as the QR product left it (A4). Refund state is carried by the
 *    DERIVED settlement_status, which is why there is no REFUNDED case on the
 *    enum.
 *
 * 2. **Lines are addressed by a key the till owns.** An offline refund is
 *    built against the till's own line ids, which the platform has never seen.
 *    A line is therefore named by `client_line_id` (what the order carried for
 *    that line) or, when the caller has the server's body in hand, by
 *    `order_item_id`. Exactly one, per line.
 *
 * 3. **The quantity check is server-authoritative and taken under a lock.**
 *    `refunded_quantity + requested > quantity` → 422 REFUND_EXCEEDS_SOLD,
 *    decided against a locked row, never against a SUM over the refund lines:
 *    two tills refunding the last portion of one line simultaneously must
 *    serialise, and one of them must lose.
 *
 * 4. **Idempotency is POS-BE-007, verbatim.** Replay returns the identical
 *    body, 200 on replay and 201 on the first write, never a 409, and a
 *    replayed key consumes no credit-note number.
 *
 * v1 relaxations follow PosOrderService: a null `acting_user_id` is accepted
 * (terminal-only attribution, per-user capability checks skipped — the device
 * token and feature gate still stand), and an unknown `shift_client_id` is
 * stored as null rather than refused over bookkeeping.
 */
class PosRefundService
{
    public function __construct(
        private readonly PosOrderService $orders,
        private readonly InvoiceSequenceService $sequences,
        private readonly PosBootstrapService $bootstrap,
    ) {}

    /** @return array{refund: PosRefund, replay: bool} */
    public function create(PosTerminal $terminal, array $data): array
    {
        $payloadHash = $this->payloadHash($data);

        // Replay first, outside the transaction: the common retry case must
        // not take a lock or touch the credit-note sequence.
        $existing = PosRefund::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->payload_hash !== $payloadHash) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['refund' => $existing, 'replay' => true];
        }

        $order = $this->orders->resolveOrder((string) $data['order_id']);
        $kind = ($data['kind'] ?? PosRefund::KIND_REFUND) === PosRefund::KIND_VOID
            ? PosRefund::KIND_VOID
            : PosRefund::KIND_REFUND;

        // The capability whose NAME matches the act. §010 wrote `pos.refund`
        // while describing the refund case; the till's own permission model
        // keeps voiding separate, and a person trusted to hand money back is
        // not automatically the person trusted to make a sale disappear.
        $actor = $this->resolveActor($terminal, $data['acting_user_id'] ?? null, $kind === PosRefund::KIND_VOID
            ? TenantCapability::POS_VOID
            : TenantCapability::POS_REFUND);

        // `authorized_by_user_id` is recorded, not enforced: the supervisor
        // ceiling is a client-side gate (§010). It must still be a real,
        // active account of this tenant, or the audit trail names a stranger.
        $authorizer = $this->resolveActor($terminal, $data['authorized_by_user_id'] ?? null, null);

        $shift = $this->resolveShift($terminal, $data['shift_client_id'] ?? null);
        $tenders = $this->resolveTenders($data['tenders'] ?? []);

        $occurredAt = Carbon::parse($data['occurred_at'])->setTimezone(config('app.timezone'));

        $refund = DB::transaction(function () use ($terminal, $order, $data, $kind, $actor, $authorizer, $shift, $tenders, $payloadHash, $occurredAt) {
            // The order row is the mutex for "how much of this sale has already
            // gone back". Two concurrent refunds serialise here.
            $locked = Order::withoutGlobalScopes()->whereKey($order->id)->lockForUpdate()->first();

            $lines = $this->resolveLines($locked, $data['lines']);
            $linesTotal = array_sum(array_column($lines, 'amount_minor'));
            $tendersTotal = array_sum(array_column($tenders, 'amount_minor'));

            // §010: the tender total must equal the line total. A refund whose
            // money and whose goods disagree is not a refund, it is two
            // mistakes; and nothing here records a give-back of value that
            // never left the drawer.
            if ($linesTotal !== $tendersTotal) {
                throw new PosApiException('VALIDATION_FAILED', 422, [
                    'errors' => ['tenders' => [
                        'Refund tenders ('.$tendersTotal.') must equal the refund lines ('.$linesTotal.').',
                    ]],
                ]);
            }

            // Cumulative money, the same invariant the till holds in a CHECK
            // constraint: a sale can never give back more than it was worth.
            $alreadyRefunded = (int) ($locked->refunded_minor ?? 0);
            $sold = (int) ($locked->total_minor ?? 0);

            if ($alreadyRefunded + $linesTotal > $sold) {
                throw new PosApiException('REFUND_EXCEEDS_SOLD', 422, [
                    'order_total_minor' => $sold,
                    'already_refunded_minor' => $alreadyRefunded,
                    'requested_minor' => $linesTotal,
                ]);
            }

            $refund = (new PosRefund)->forceFill([
                'restaurant_id' => $terminal->restaurant_id,
                'branch_id' => $locked->branch_id ?? $terminal->branch_id,
                'order_id' => $locked->id,
                'pos_terminal_id' => $terminal->id,
                'pos_shift_id' => $shift?->id,
                'acting_user_id' => $actor?->id,
                'authorized_by_user_id' => $authorizer?->id,
                'client_transaction_id' => $data['client_transaction_id'],
                'credit_note_number' => $this->sequences->next(
                    $locked->branch ?? $terminal->branch,
                    $occurredAt,
                    $this->bootstrap->invoiceConfig($terminal->restaurant),
                    'CN',
                ),
                'kind' => $kind,
                'reason' => $data['reason'] ?? null,
                'total_minor' => $linesTotal,
                'currency' => $locked->currency,
                'occurred_at' => $occurredAt,
                'received_at' => now(),
                'payload_hash' => $payloadHash,
            ]);
            $refund->save();

            foreach ($lines as $line) {
                (new PosRefundLine)->forceFill([
                    'restaurant_id' => $terminal->restaurant_id,
                    'pos_refund_id' => $refund->id,
                    'order_item_id' => $line['item']->id,
                    'quantity' => $line['quantity'],
                    'unit_price_minor' => (int) ($line['item']->unit_price_minor ?? 0),
                    'amount_minor' => $line['amount_minor'],
                    'name_snapshot' => $line['item']->name,
                ])->save();

                // The counter, under the same transaction as the record that
                // explains it.
                OrderItem::withoutGlobalScopes()
                    ->whereKey($line['item']->id)
                    ->increment('refunded_quantity', $line['quantity']);
            }

            foreach ($tenders as $tender) {
                (new PosRefundTender)->forceFill([
                    'restaurant_id' => $terminal->restaurant_id,
                    'pos_refund_id' => $refund->id,
                    'tender_type_id' => $tender['tender_type_id'],
                    'amount_minor' => $tender['amount_minor'],
                ])->save();
            }

            Order::withoutGlobalScopes()->whereKey($locked->id)->increment('refunded_minor', $linesTotal);

            return $refund;
        });

        AuditLogger::record('pos_refund.created', [
            'restaurant_id' => $refund->restaurant_id,
            'actor' => $actor,
            'actor_role' => $actor === null ? 'TERMINAL' : null,
            'auditable' => $refund,
            'description' => sprintf('POS %s %s against order %s', $kind, $refund->credit_note_number, $order->invoice_number),
            'properties' => [
                'credit_note_number' => $refund->credit_note_number,
                'kind' => $kind,
                'total_minor' => $refund->total_minor,
                'order_id' => $order->id,
                'invoice_number' => $order->invoice_number,
                'reason' => $refund->reason,
                'authorized_by_user_id' => $refund->authorized_by_user_id,
                'terminal' => $terminal->terminal_id,
            ],
        ]);

        return ['refund' => $refund, 'replay' => false];
    }

    /**
     * Resolve each requested line to an order item of THIS order, and hold it
     * to the sold quantity.
     *
     * @return list<array{item: OrderItem, quantity: int, amount_minor: int}>
     */
    private function resolveLines(Order $order, array $requested): array
    {
        // Locked for the same reason the order row is: the quantity check is
        // only sound if nothing else can move the counter between the read and
        // the increment.
        $items = OrderItem::withoutGlobalScopes()
            ->where('order_id', $order->id)
            ->lockForUpdate()
            ->get();

        $byId = $items->keyBy('id');
        $byClientLine = $items->whereNotNull('client_line_id')->keyBy('client_line_id');

        $resolved = [];

        foreach (array_values($requested) as $index => $line) {
            $item = null;

            if (isset($line['order_item_id'])) {
                $item = $byId->get((int) $line['order_item_id']);
            } elseif (isset($line['client_line_id'])) {
                $item = $byClientLine->get((string) $line['client_line_id']);
            }

            if ($item === null) {
                // A line of another tenant's order, of another order, or a key
                // this order never carried: all the same answer, and none of
                // them leaks whether the id exists somewhere else.
                throw new PosApiException('VALIDATION_FAILED', 422, [
                    'errors' => ["lines.$index" => ['This line is not on that order.']],
                ]);
            }

            $quantity = (int) $line['quantity'];
            $already = (int) ($item->refunded_quantity ?? 0);

            if ($already + $quantity > (int) $item->quantity) {
                throw new PosApiException('REFUND_EXCEEDS_SOLD', 422, [
                    'order_item_id' => $item->id,
                    'client_line_id' => $item->client_line_id,
                    'sold_quantity' => (int) $item->quantity,
                    'already_refunded_quantity' => $already,
                    'requested_quantity' => $quantity,
                ]);
            }

            $resolved[] = [
                'item' => $item,
                'quantity' => $quantity,
                'amount_minor' => (int) $line['amount_minor'],
            ];
        }

        return $resolved;
    }

    /**
     * Refund tenders must be this tenant's own POS-BE-013 tender types — the
     * same rule a payment obeys, for the same reason: the ids are the
     * platform's, never the till's local ones.
     *
     * @return list<array{tender_type_id: int|null, amount_minor: int}>
     */
    private function resolveTenders(array $tenders): array
    {
        $ids = collect($tenders)->pluck('tender_type_id')->filter()->unique()->values();

        if ($ids->isNotEmpty() && TenderType::whereIn('id', $ids)->count() !== $ids->count()) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['tenders' => ['Unknown tender type.']],
            ]);
        }

        return array_map(fn ($t) => [
            'tender_type_id' => isset($t['tender_type_id']) ? (int) $t['tender_type_id'] : null,
            'amount_minor' => (int) $t['amount_minor'],
        ], array_values($tenders));
    }

    /**
     * v1 relaxation, as on orders: null actor ⇒ terminal-only attribution and
     * no per-user capability check. A NAMED actor must be real, active and of
     * this tenant. `$required` is null for the authoriser, who is recorded
     * rather than gated.
     */
    private function resolveActor(PosTerminal $terminal, ?int $userId, ?TenantCapability $required): ?User
    {
        if ($userId === null) {
            return null;
        }

        $user = User::where('restaurant_id', $terminal->restaurant_id)
            ->where('status', UserStatus::ACTIVE)
            ->find($userId);

        if ($user === null || ! $user->isTenantUser()) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['acting_user_id' => ['Unknown user.']],
            ]);
        }

        if ($required !== null && ! $user->holdsTenantCapability($required)) {
            throw new PosApiException('POS_CAPABILITY_MISSING', 403, ['capability' => $required->value]);
        }

        return $user;
    }

    /** Unknown ⇒ null, never a rejection: the platform may not have seen the till's shift yet. */
    private function resolveShift(PosTerminal $terminal, ?string $shiftClientId): ?PosShift
    {
        if ($shiftClientId === null) {
            return null;
        }

        return PosShift::where('pos_terminal_id', $terminal->id)
            ->where('client_transaction_id', $shiftClientId)
            ->first();
    }

    /**
     * The canonical hash of the money-bearing fields (POS-BE-007). Key order is
     * fixed by construction, so equal money always hashes equal. Line identity
     * is included: refunding line A instead of line B is a different refund.
     */
    private function payloadHash(array $data): string
    {
        return hash('sha256', json_encode([
            $data['client_transaction_id'],
            (string) $data['order_id'],
            $data['kind'] ?? PosRefund::KIND_REFUND,
            array_map(fn ($l) => [
                $l['order_item_id'] ?? null,
                $l['client_line_id'] ?? null,
                (int) $l['quantity'],
                (int) $l['amount_minor'],
            ], array_values($data['lines'])),
            array_map(fn ($t) => [
                $t['tender_type_id'] ?? null,
                (int) $t['amount_minor'],
            ], array_values($data['tenders'] ?? [])),
        ]));
    }
}
