<?php

namespace App\Services;

use App\Enums\OrderStatus;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Exceptions\PosApiException;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\DiningTable;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderPayment;
use App\Models\OrderRound;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * POS-BE-006/007 (+ BE-A01 / §006-P): authenticated, server-priced order
 * creation on the EXISTING order graph, idempotent to the letter of the
 * contract — five submissions of one client_transaction_id create exactly one
 * record and all five get the same 2xx body, invoice number included. Replay
 * is never 409; same key with a different money payload is the one genuine
 * client bug (422 IDEMPOTENCY_PAYLOAD_MISMATCH).
 *
 * v1 relaxations (2026-09-02 amendment, recorded in §006): acting_user_id and
 * shift_client_id are nullable — a drained offline order may predate sign-in
 * enforcement or reference a shift the platform never saw. Null actor ⇒
 * terminal-only attribution, per-user capability checks skipped (the device
 * token + feature:pos still gate); unknown shift ⇒ stored null, never a
 * rejection over bookkeeping.
 */
class PosOrderService
{
    public function __construct(
        private readonly PosPricingEngine $pricing,
        private readonly InvoiceSequenceService $invoices,
        private readonly PosBootstrapService $bootstrap,
    ) {}

    /** @return array{order: Order, replay: bool} */
    public function create(PosTerminal $terminal, array $data): array
    {
        $payloadHash = $this->orderPayloadHash($data);

        // Replay first, outside the transaction: the common retry case must
        // not touch the sequence or take locks.
        $existing = Order::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->payload_hash !== $payloadHash) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['order' => $existing, 'replay' => true];
        }

        $branch = Branch::find($data['branch_id']);

        if ($branch === null) {
            // 404, not 403 — a foreign branch id is invisible, not forbidden.
            throw new PosApiException('BRANCH_NOT_IN_TENANT', 404);
        }

        // A customer on the ticket must be this restaurant's own. After the
        // replay short-circuit (a stored order is returned as stored, never
        // re-judged) and before anything is written. A walk-in carries none.
        $customer = $this->customerInTenant($terminal, $data['customer_id'] ?? null);

        // Two vocabularies, one meaning. The onboarding wizard and the plan
        // features write `pickup`; the POS sends `takeaway`. They are the same
        // act, and a branch onboarded through the wizard must not have its
        // takeaway orders refused because two screens disagree about a word.
        // Normalised rather than migrated: production branches already hold
        // `pickup`, and rewriting live rows to fix a naming split is a bigger
        // risk than accepting both spellings forever.
        $synonyms = ['pickup' => 'takeaway', 'take_away' => 'takeaway'];
        $normalise = static fn (string $type): string => $synonyms[$type] ?? $type;

        $supported = array_map($normalise, $branch->supported_order_types ?? []);
        $requested = $normalise($data['order_type']);

        if ($supported !== [] && ! in_array($requested, $supported, true)) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['order_type' => ['This branch does not support '.$data['order_type'].'.']],
            ]);
        }

        $actor = $this->resolveActor($terminal, $data['acting_user_id'] ?? null, [
            TenantCapability::POS_OPERATE,
            ...(collect($data['lines'])->contains(fn ($l) => isset($l['discount'])) || ($data['order_discount']['amount_minor'] ?? 0) > 0
                ? [TenantCapability::POS_DISCOUNT] : []),
            ...(collect($data['lines'])->contains(fn ($l) => isset($l['price_override']))
                ? [TenantCapability::POS_PRICE_OVERRIDE] : []),
        ]);

        $shift = $this->resolveShift($terminal, $data['shift_client_id'] ?? null);
        $this->assertTenders($data['payments'] ?? []);

        $restaurant = $terminal->restaurant;
        $currency = $restaurant->currency;
        $exp = 10 ** $currency->exponent();

        $priced = $this->pricing->price(
            $branch,
            $data['order_type'],
            $data['lines'],
            (int) ($data['order_discount']['amount_minor'] ?? 0),
            $currency,
        );

        // **The same bar `addPayment` holds, held at the door too.** Settling a
        // bill later is refused when it exceeds the outstanding balance; an
        // order that arrives settled had no such check, so the one path that
        // could write an impossible ledger state was the one nobody guarded.
        //
        // Found on 27 Sep 2026: `BR8-2026-000007` landed as 380.00 of payment
        // against a 360.00 sale, because the till was writing cash TENDERED
        // where its own contract says a payment row records what was APPLIED
        // (`payment_status.dart`). The till is fixed; this is the half that
        // means a till with that bug cannot put the platform's ledger in a
        // state `settlementStatusFrom` has no word for.
        //
        // Against the SERVER's total, never the asserted one — a client that
        // gets the total wrong does not also get to set the bar it is measured
        // against.
        $tendered = array_sum(array_map(
            static fn ($payment) => (int) ($payment['amount_minor'] ?? 0),
            $data['payments'] ?? [],
        ));

        if ($tendered > $priced['totals']['total_minor']) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['payments' => [
                    'Payments total '.$tendered.', which exceeds the order total of '
                        .$priced['totals']['total_minor'].'. A payment records what was '
                        .'applied to the bill, not what was tendered.',
                ]],
            ]);
        }

        $asserted = $data['asserted_totals'] ?? null;
        $mismatch = $asserted !== null && array_diff_assoc(
            array_map('intval', $asserted),
            $priced['totals'],
        ) !== [];

        // Parse then NORMALISE to the app timezone: Eloquent formats a Carbon
        // in its own tz without converting, so a "+02:00" instant stored raw
        // would silently shift by two hours on read-back. The instant is what
        // is preserved; the original utc-offset is not (recorded in §006).
        $clientCreatedAt = Carbon::parse($data['created_at'])->setTimezone(config('app.timezone'));

        $order = DB::transaction(function () use ($terminal, $branch, $data, $priced, $mismatch, $asserted, $actor, $shift, $restaurant, $currency, $exp, $payloadHash, $clientCreatedAt, $customer) {
            $invoiceNumber = $this->invoices->next(
                $branch,
                $clientCreatedAt,
                $this->bootstrap->invoiceConfig($restaurant),
            );

            $table = null;
            if (! empty($data['table_id'])) {
                $table = DiningTable::find($data['table_id']);
                if ($table === null) {
                    throw new PosApiException('VALIDATION_FAILED', 422, [
                        'errors' => ['table_id' => ['Unknown table.']],
                    ]);
                }
            }

            $order = new Order([
                // Provisional. A sale that arrives already settled is moved to
                // COMPLETED once its payments are stored, below — the paid
                // total is not known until then.
                'status' => OrderStatus::NEW->value,
                'currency' => $currency->value,
                'order_type' => $data['order_type'],
                'note' => $data['note'] ?? null,
                'source' => 'pos',
                'branch_id' => $branch->id,
                'customer_id' => $data['customer_id'] ?? null,
                // G2: the dashboard's customer column reads these, as it does
                // for a diner's order — a snapshot of who the sale was for, as
                // the record read when it was rung up. A walk-in has none.
                'customer_name' => $customer?->name,
                'customer_phone' => $customer?->phone,
                // Legacy projection so the dashboard renders POS orders with
                // zero changes: same shape the public path stores.
                'items' => array_map(fn ($l) => [
                    'name' => $l['name'],
                    // R1: both languages carried in the legacy projection so the
                    // dashboard resolves the line name by locale without a join.
                    'name_ar' => $l['name_ar'],
                    'name_en' => $l['name_en'],
                    'qty' => $l['quantity'],
                    'options' => $l['options'],
                    'note' => $l['note'],
                    'line_total' => $l['line_total_minor'] / $exp,
                ], $priced['lines']),
                'total' => min($priced['totals']['total_minor'] / $exp, 99999999.99),
            ]);

            $order->restaurant_id = $terminal->restaurant_id;
            if ($table !== null) {
                $order->table_id = $table->id;
                $order->dining_area_id = $table->dining_area_id;

                // Dine-in against a seated table: reuse the existing visit
                // lock discipline so a QR round and a POS ticket cannot race.
                $visit = $table->visits()->where('status', 'OPEN')->lockForUpdate()->first();
                if ($visit !== null) {
                    $order->table_visit_id = $visit->id;
                }
            }

            $order->forceFill([
                'channel' => 'pos',
                'client_transaction_id' => $data['client_transaction_id'],
                'invoice_number' => $invoiceNumber,
                'subtotal_minor' => $priced['totals']['subtotal_minor'],
                'discount_minor' => $priced['totals']['discount_minor'],
                'tax_minor' => $priced['totals']['tax_minor'],
                'charges_minor' => $priced['totals']['charges_minor'],
                'total_minor' => $priced['totals']['total_minor'],
                'pos_terminal_id' => $terminal->id,
                'pos_shift_id' => $shift?->id,
                'acting_user_id' => $actor?->id,
                'received_at' => now(),
                'payload_hash' => $payloadHash,
                'pos_meta' => [
                    'asserted_totals' => $asserted,
                    'totals_mismatch' => $mismatch,
                    'priced_offline' => (bool) ($data['priced_offline'] ?? false),
                    'catalog_synced_at' => $data['catalog_synced_at'] ?? null,
                    // v1 relaxation: who the money is attributed to when no
                    // cashier could be named.
                    'attribution' => $actor === null ? 'terminal' : 'user',
                ],
                // The client's event time, stored as sent (POS-BE-020).
                'created_at' => $clientCreatedAt,
            ])->save();

            $round = new OrderRound([
                'order_id' => $order->id,
                'sequence' => 1,
                'total' => $order->total,
                'note' => $data['note'] ?? null,
                'submitted_at' => $clientCreatedAt,
            ]);
            $round->restaurant_id = $order->restaurant_id;
            $round->save();

            foreach ($priced['lines'] as $line) {
                $item = new OrderItem([
                    'order_id' => $order->id,
                    'order_round_id' => $round->id,
                    'name' => $line['name'],
                    'name_ar' => $line['name_ar'],
                    'name_en' => $line['name_en'],
                    'quantity' => $line['quantity'],
                    'options' => $line['options'],
                    'note' => $line['note'],
                    'unit_price' => $line['unit_price_minor'] / $exp,
                    'line_total' => $line['line_total_minor'] / $exp,
                ]);
                $item->restaurant_id = $order->restaurant_id;
                $item->forceFill([
                    'menu_item_id' => $line['menu_item_id'],
                    'unit_price_minor' => $line['unit_price_minor'],
                    'line_total_minor' => $line['line_total_minor'],
                    'price_source' => $line['price_source'],
                    // POS-BE-010: the till's own key for this line, stored
                    // verbatim so a refund built offline can name it without
                    // ever having seen order_items.id.
                    'client_line_id' => $line['client_line_id'],
                ])->save();
            }

            foreach ($data['payments'] ?? [] as $payment) {
                $this->storePayment($order, $terminal, $shift, $actor, $payment, $currency->value);
            }

            $this->completeIfSettled($order);

            return $order;
        });

        AuditLogger::record('pos_order.created', [
            'restaurant_id' => $order->restaurant_id,
            'actor' => $actor,
            'actor_role' => $actor === null ? 'TERMINAL' : null,
            'auditable' => $order,
            'description' => sprintf('POS order %s created', $order->invoice_number),
            'properties' => [
                'invoice_number' => $order->invoice_number,
                'total_minor' => $order->total_minor,
                'totals_mismatch' => $mismatch,
                'terminal' => $terminal->terminal_id,
            ],
        ]);

        return ['order' => $order, 'replay' => false];
    }

    /**
     * §006-P — settle an open bill later, possibly from another terminal. The
     * payment row carries its OWN client_transaction_id (decision a).
     *
     * @return array{payment: OrderPayment, order: Order, replay: bool}
     */
    public function addPayment(PosTerminal $terminal, string $orderRef, array $data): array
    {
        $order = $this->resolveOrder($orderRef);
        $payloadHash = $this->paymentPayloadHash($data);

        $existing = OrderPayment::where('client_transaction_id', $data['client_transaction_id'])->first();

        if ($existing !== null) {
            if ($existing->payload_hash !== $payloadHash) {
                throw new PosApiException('IDEMPOTENCY_PAYLOAD_MISMATCH', 422);
            }

            return ['payment' => $existing, 'order' => $order, 'replay' => true];
        }

        $actor = $this->resolveActor($terminal, $data['acting_user_id'] ?? null, [TenantCapability::POS_OPERATE]);
        $shift = $this->resolveShift($terminal, $data['shift_client_id'] ?? null);
        $this->assertTenders([$data]);

        $outstanding = $order->total_minor - (int) OrderPayment::where('order_id', $order->id)->sum('amount_minor');

        if ((int) $data['amount_minor'] > $outstanding) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['amount_minor' => ['Exceeds the outstanding balance of '.$outstanding.'.']],
            ]);
        }

        $payment = DB::transaction(function () use ($order, $terminal, $shift, $actor, $data, $payloadHash) {
            $stored = $this->storePayment(
                $order, $terminal, $shift, $actor, $data, $order->currency, $payloadHash,
            );

            // In the SAME transaction as the payment that settles it: a bill
            // left open at the counter and paid on the way out reaches PAID
            // here rather than at ingest, and it has exactly as little to
            // confirm as one that arrived settled.
            $this->completeIfSettled($order);

            return $stored;
        });

        return ['payment' => $payment, 'order' => $order, 'replay' => false];
    }

    /**
     * A settled sale leaves the confirmation queue.
     *
     * **Money already taken is not a request.** The sale happened at the
     * counter, the receipt printed, the customer left; the till is reporting
     * it, not asking permission. Ingested as NEW it sat in the dashboard's
     * "new orders" list behind a "Mark received" button, counted in every
     * new-order badge (`StatsController`, `PulseController`,
     * `OrderController`), and lit the table it was rung up against as having
     * an order waiting — all of it work nobody could act on, and a sales
     * figure that read as pending.
     *
     * **Only a settled one, and only from NEW.** A POS ticket sent to the
     * kitchen against an open table is genuinely still open, so an unpaid one
     * stays NEW — which is what keeps `TableController`'s seated-table marker
     * honest. The NEW guard also means a CANCELLED order that somehow receives
     * a payment is never quietly completed: `canTransitionTo` permits that
     * move, but only a person should make it.
     *
     * Nothing else moves. `settlement_status` stays the derived answer it has
     * always been (A5/A4) — this writes the QR product's own NEW → COMPLETED
     * transition, and the till neither sends nor reads `status`.
     */
    private function completeIfSettled(Order $order): void
    {
        if ($order->status === OrderStatus::NEW && $this->settlementStatus($order) === 'PAID') {
            // Paid in full on the till: completed now, by the cashier who rang
            // it up (null for a terminal-only sale). Stamped outside $fillable.
            $order->forceFill([
                'status' => OrderStatus::COMPLETED->value,
                'completed_at' => now(),
                'completed_by' => $order->acting_user_id,
            ])->save();
        }
    }

    /** A5/A4: settlement is DERIVED, never a stored lifecycle state. */
    public function settlementStatus(Order $order): string
    {
        return self::settlementStatusFrom(
            (int) ($order->total_minor ?? 0),
            (int) OrderPayment::where('order_id', $order->id)->sum('amount_minor'),
            (int) ($order->refunded_minor ?? 0),
        );
    }

    /**
     * The derivation, in one place, from figures the caller already has.
     *
     * **A refund outranks everything before it** (POS-BE-010): once money has
     * gone back, "how much went back" is the question being asked, and
     * answering PAID for a sale half of which was returned is the stale answer.
     * Measured against what was TAKEN, not against the total — a part-paid sale
     * whose whole part came back has nothing of the customer's left, which is
     * REFUNDED, not PARTIALLY_REFUNDED. This is the till's own rule, verbatim
     * (xorder-pos `domain/services/payment_status.dart::paymentStatusFromSums`),
     * so the till parses these words with the enum it already ships.
     *
     * PARTIALLY_PAID is deliberately NOT emitted: the shipped §006 contract
     * answers UNPAID for every incompletely settled bill, and changing an
     * existing value is not something a refund wave gets to do. `status`
     * (OrderStatus) is untouched by all of this — NEW | COMPLETED | CANCELLED,
     * exactly as the QR product left it.
     */
    public static function settlementStatusFrom(int $totalMinor, int $paidMinor, int $refundedMinor): string
    {
        if ($refundedMinor > 0) {
            return $refundedMinor >= $paidMinor ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
        }

        return $paidMinor >= $totalMinor && $totalMinor > 0 ? 'PAID' : 'UNPAID';
    }

    /** Server id or the order's own client uuid — both are how a till knows an order. */
    public function resolveOrder(string $ref): Order
    {
        $order = preg_match('/^\d+$/', $ref) === 1
            ? Order::where('channel', 'pos')->find((int) $ref)
            : Order::where('channel', 'pos')->where('client_transaction_id', $ref)->first();

        if ($order === null) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['order' => ['Unknown POS order.']],
            ]);
        }

        return $order;
    }

    private function storePayment(
        Order $order,
        PosTerminal $terminal,
        ?PosShift $shift,
        ?User $actor,
        array $data,
        string $currency,
        ?string $payloadHash = null,
    ): OrderPayment {
        $payment = (new OrderPayment)->forceFill([
            'restaurant_id' => $order->restaurant_id,
            'order_id' => $order->id,
            'pos_shift_id' => $shift?->id ?? $order->pos_shift_id,
            'pos_terminal_id' => $terminal->id,
            'acting_user_id' => $actor?->id,
            'client_transaction_id' => $data['client_transaction_id'],
            'tender_type_id' => $data['tender_type_id'] ?? null,
            'amount_minor' => (int) $data['amount_minor'],
            'currency' => $currency,
            'received_at' => isset($data['received_at'])
                ? Carbon::parse($data['received_at'])->setTimezone(config('app.timezone'))
                : null,
            'received_server_at' => now(),
            'payload_hash' => $payloadHash ?? $this->paymentPayloadHash($data),
        ]);
        $payment->save();

        return $payment;
    }

    /**
     * v1 relaxation: null actor is accepted (terminal-only attribution, no
     * capability checks — the device token + feature gate still stand). A
     * NAMED actor must be real, active, of this tenant, and hold every
     * required verb; the owner bypasses per holdsTenantCapability.
     *
     * @param  list<TenantCapability>  $required
     */
    private function resolveActor(PosTerminal $terminal, ?int $userId, array $required): ?User
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

        foreach ($required as $capability) {
            if (! $user->holdsTenantCapability($capability)) {
                throw new PosApiException('POS_CAPABILITY_MISSING', 403, [
                    'capability' => $capability->value,
                ]);
            }
        }

        AuditLogger::attachPosActingUser($user);

        return $user;
    }

    /**
     * v1 relaxation: null or unknown ⇒ null, never a rejection — the platform
     * may simply not have seen the till's local shift yet.
     */
    private function resolveShift(PosTerminal $terminal, ?string $shiftClientId): ?PosShift
    {
        if ($shiftClientId === null) {
            return null;
        }

        return PosShift::where('pos_terminal_id', $terminal->id)
            ->where('client_transaction_id', $shiftClientId)
            ->where('status', PosShift::STATUS_OPEN)
            ->first();
    }

    /** @param list<array<string,mixed>> $payments */
    private function assertTenders(array $payments): void
    {
        $ids = collect($payments)->pluck('tender_type_id')->filter()->unique()->values();

        if ($ids->isEmpty()) {
            return;
        }

        $known = TenderType::whereIn('id', $ids)->pluck('id');

        if ($known->count() !== $ids->count()) {
            throw new PosApiException('VALIDATION_FAILED', 422, [
                'errors' => ['payments' => ['Unknown tender type.']],
            ]);
        }
    }

    /**
     * `customer_id` is the platform's own id (the till uploads the customer
     * first). Looked up against the TERMINAL's restaurant explicitly rather
     * than through the global scope, so the answer does not depend on which
     * tenant the request context happens to have pinned. A customer of another
     * restaurant and one that never existed get the same answer. Returns the
     * customer (null for a walk-in) so the order can carry its name and phone.
     */
    private function customerInTenant(PosTerminal $terminal, mixed $customerId): ?Customer
    {
        if ($customerId === null) {
            return null;
        }

        $customer = Customer::withoutGlobalScopes()
            ->where('restaurant_id', $terminal->restaurant_id)
            ->whereKey((int) $customerId)
            ->first(['id', 'name', 'phone']);

        if ($customer === null) {
            throw new PosApiException('CUSTOMER_NOT_FOUND', 422);
        }

        return $customer;
    }

    /**
     * The canonical hash of the money-bearing fields (POS-BE-007). Key order
     * is fixed by construction, so equal money always hashes equal.
     */
    private function orderPayloadHash(array $data): string
    {
        return hash('sha256', json_encode([
            $data['client_transaction_id'],
            (int) $data['branch_id'],
            $data['order_type'],
            array_map(fn ($l) => [
                $l['menu_item_id'] ?? null,
                $l['variant_option_id'] ?? null,
                collect($l['option_ids'] ?? [])->map(fn ($i) => (int) $i)->sort()->values()->all(),
                (int) $l['quantity'],
                (int) ($l['discount']['amount_minor'] ?? 0),
                isset($l['price_override']) ? (int) $l['price_override']['unit_price_minor'] : null,
                (int) ($l['unit_price_minor'] ?? 0),
            ], array_values($data['lines'])),
            (int) ($data['order_discount']['amount_minor'] ?? 0),
            array_map(fn ($p) => [
                $p['client_transaction_id'],
                $p['tender_type_id'] ?? null,
                (int) $p['amount_minor'],
            ], array_values($data['payments'] ?? [])),
        ]));
    }

    private function paymentPayloadHash(array $data): string
    {
        return hash('sha256', json_encode([
            $data['client_transaction_id'],
            $data['tender_type_id'] ?? null,
            (int) $data['amount_minor'],
        ]));
    }
}
