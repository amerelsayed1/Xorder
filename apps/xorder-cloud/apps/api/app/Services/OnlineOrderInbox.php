<?php

namespace App\Services;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Exceptions\PosApiException;
use App\Models\BillRequest;
use App\Models\Order;
use App\Models\PosTerminal;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * POS-BE-033 — what a till sees of the cloud's online orders and table
 * requests, and what it may do with them.
 *
 * Scope is the device token's: the tenant is pinned by `pos.device`, and the
 * branch is the terminal's own — a till never reads or touches another
 * branch's rows, and a row outside its scope is a 404, not a 403, so it cannot
 * be used to probe for ids. The feed is empty, and the actions refused, while
 * the branch's `online_orders_on_pos` switch is off.
 *
 * Accepted is not an order status: an accepted online order is NEW with
 * `accepted_at` set. First writer wins under `lockForUpdate`; the same till
 * repeating the same `client_request_id` gets the same answer.
 */
class OnlineOrderInbox
{
    /** Events per feed read; `has_more` tells the till to read again at once. */
    public const PAGE = 100;

    /** `last_feed_at` is telemetry, not a poll counter: written at most this often. */
    private const STAMP_EVERY_SECONDS = 20;

    /**
     * @return array{events: list<array{kind:string,model:Order|BillRequest}>, cursor: string|null, has_more: bool}
     */
    public function feed(PosTerminal $terminal, ?string $cursor, ?string $appVersion): array
    {
        $this->stamp($terminal, $appVersion);

        $state = $this->decodeCursor($cursor);

        if (! $this->enabled($terminal)) {
            return ['events' => [], 'cursor' => $cursor, 'has_more' => false];
        }

        $orders = $this->since($this->orderQuery($terminal), $state['o'])
            ->when($cursor === null, fn (Builder $q) => $q->where('status', OrderStatus::NEW->value))
            ->limit(self::PAGE + 1)->get();

        $requests = $this->since($this->requestQuery($terminal), $state['b'])
            ->when($cursor === null, fn (Builder $q) => $q->whereIn('status', [
                BillRequestStatus::REQUESTED->value, BillRequestStatus::SEEN->value, BillRequestStatus::IN_PROGRESS->value,
            ]))
            ->limit(self::PAGE + 1)->get();

        $hasMore = $orders->count() > self::PAGE || $requests->count() > self::PAGE;
        // Rows re-read at the cursor's own second that were already delivered are dropped.
        $orders = $this->unseen($orders->take(self::PAGE), $state['o'], fn (Order $o) => $this->orderFingerprint($o));
        $requests = $this->unseen($requests->take(self::PAGE), $state['b'], fn (BillRequest $r) => $this->requestFingerprint($r));

        $events = [];
        foreach ($orders as $o) {
            $events[] = ['kind' => 'online_order', 'model' => $o];
        }
        foreach ($requests as $r) {
            $events[] = ['kind' => 'table_request', 'model' => $r];
        }
        usort($events, fn ($a, $b) => [$a['model']->updated_at, $a['model']->id] <=> [$b['model']->updated_at, $b['model']->id]);

        return [
            'events' => $events,
            'cursor' => $this->encodeCursor([
                'o' => $this->position($state['o'], $orders, fn (Order $o) => $this->orderFingerprint($o)),
                'b' => $this->position($state['b'], $requests, fn (BillRequest $r) => $this->requestFingerprint($r)),
            ]),
            'has_more' => $hasMore,
        ];
    }

    public function accept(PosTerminal $terminal, int $orderId, string $requestId): Order
    {
        return DB::transaction(function () use ($terminal, $orderId, $requestId) {
            $order = $this->lockOrder($terminal, $orderId);

            if ($order->rejected_at !== null) {
                throw new PosApiException('ALREADY_REJECTED', 409);
            }

            if ($order->accepted_at !== null) {
                if ($order->accepted_by_terminal_id === $terminal->id && $order->accept_client_request_id === $requestId) {
                    return $order;
                }
                throw new PosApiException('ALREADY_ACCEPTED', 409);
            }

            if ($order->status !== OrderStatus::NEW) {
                throw new PosApiException('ORDER_NOT_PENDING', 409);
            }

            $order->forceFill([
                'accepted_at' => now(),
                'accepted_by_terminal_id' => $terminal->id,
                'accept_client_request_id' => $requestId,
            ])->save();

            return $order;
        });
    }

    public function reject(PosTerminal $terminal, int $orderId, string $requestId, string $reason): Order
    {
        return DB::transaction(function () use ($terminal, $orderId, $requestId, $reason) {
            $order = $this->lockOrder($terminal, $orderId);

            if ($order->accepted_at !== null) {
                throw new PosApiException('ALREADY_ACCEPTED', 409);
            }

            if ($order->rejected_at !== null) {
                if ($order->reject_client_request_id === $requestId) {
                    return $order;
                }
                throw new PosApiException('ALREADY_REJECTED', 409);
            }

            if ($order->status !== OrderStatus::NEW) {
                throw new PosApiException('ORDER_NOT_PENDING', 409);
            }

            $order->forceFill([
                'status' => OrderStatus::CANCELLED,
                'rejected_at' => now(),
                'reject_reason' => $reason,
                'reject_client_request_id' => $requestId,
            ])->save();

            return $order;
        });
    }

    public function handled(PosTerminal $terminal, int $requestId, string $clientRequestId): BillRequest
    {
        return DB::transaction(function () use ($terminal, $requestId, $clientRequestId) {
            $this->assertEnabled($terminal);

            $request = $this->requestQuery($terminal)->lockForUpdate()->find($requestId);
            if ($request === null) {
                throw new PosApiException('NOT_FOUND', 404);
            }

            if ($request->status === BillRequestStatus::COMPLETED && $request->handled_by_terminal_id !== null) {
                if ($request->handled_by_terminal_id === $terminal->id && $request->handled_client_request_id === $clientRequestId) {
                    return $request;
                }
                throw new PosApiException('ALREADY_HANDLED', 409);
            }

            if (! $request->status->isOpen()) {
                throw new PosApiException('ALREADY_HANDLED', 409);
            }

            $request->forceFill([
                'status' => BillRequestStatus::COMPLETED,
                'completed_at' => now(),
                'handled_by_terminal_id' => $terminal->id,
                'handled_client_request_id' => $clientRequestId,
            ])->save();

            return $request;
        });
    }

    // ── scope ───────────────────────────────────────────────────────────

    private function enabled(PosTerminal $terminal): bool
    {
        return (bool) $terminal->branch()->value('online_orders_on_pos');
    }

    private function assertEnabled(PosTerminal $terminal): void
    {
        if (! $this->enabled($terminal)) {
            throw new PosApiException('ONLINE_ORDERS_NOT_ON_POS', 403);
        }
    }

    /** Online (diner) orders of this terminal's branch; tenant scope comes from the device middleware. */
    private function orderQuery(PosTerminal $terminal): Builder
    {
        return Order::query()
            ->with('customerAddress')
            ->where('restaurant_id', $terminal->restaurant_id)
            ->where('branch_id', $terminal->branch_id)
            // A running dine-in bill belongs to its table visit and is closed with it
            // (Dashboard\OrderController refuses to touch it); never a till decision.
            ->whereNull('table_visit_id')
            ->where('source', 'system');
    }

    private function requestQuery(PosTerminal $terminal): Builder
    {
        return BillRequest::query()
            ->where('restaurant_id', $terminal->restaurant_id)
            ->where('branch_id', $terminal->branch_id);
    }

    private function lockOrder(PosTerminal $terminal, int $orderId): Order
    {
        $this->assertEnabled($terminal);

        $order = $this->orderQuery($terminal)->lockForUpdate()->find($orderId);
        if ($order === null) {
            throw new PosApiException('NOT_FOUND', 404);
        }

        return $order;
    }

    // ── cursor ──────────────────────────────────────────────────────────
    //
    // One position per table: the newest `updated_at` already delivered plus the
    // fingerprints of rows delivered AT that second. Re-reading `>= ts` and
    // dropping fingerprints already seen gives each change exactly once, even
    // when two rows change inside the same second (a plain `(ts, id) >` would
    // lose the lower id).

    /** @return array{o: array{ts:?string,seen:list<string>}, b: array{ts:?string,seen:list<string>}} */
    private function decodeCursor(?string $cursor): array
    {
        $empty = ['ts' => null, 'seen' => []];
        if ($cursor === null || $cursor === '') {
            return ['o' => $empty, 'b' => $empty];
        }

        $data = json_decode((string) base64_decode(strtr($cursor, '-_', '+/'), true), true);
        if (! is_array($data)) {
            throw new PosApiException('INVALID_CURSOR', 422);
        }

        // `ts` is bound into a timestamp comparison: anything but our own format
        // would be a 500 on PostgreSQL (SQLite compares strings and would not say).
        $pick = function ($p) use ($empty) {
            if (! is_array($p)) {
                return $empty;
            }
            $ts = $p['ts'] ?? null;
            if ($ts !== null && (! is_string($ts) || ! preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $ts))) {
                throw new PosApiException('INVALID_CURSOR', 422);
            }
            $seen = array_values(array_filter((array) ($p['seen'] ?? []), fn ($x) => is_string($x) && strlen($x) <= 64));

            return ['ts' => $ts, 'seen' => array_slice($seen, 0, 300)];
        };

        return ['o' => $pick($data['o'] ?? null), 'b' => $pick($data['b'] ?? null)];
    }

    private function encodeCursor(array $state): string
    {
        return rtrim(strtr(base64_encode(json_encode($state)), '+/', '-_'), '=');
    }

    /** @param array{ts:?string,seen:list<string>} $pos */
    private function since(Builder $query, array $pos): Builder
    {
        if ($pos['ts'] !== null) {
            $query->where('updated_at', '>=', $pos['ts']);
        }

        return $query->orderBy('updated_at')->orderBy('id');
    }

    /** @param array{ts:?string,seen:list<string>} $pos */
    private function unseen($rows, array $pos, callable $fingerprint)
    {
        return $rows->filter(fn ($r) => ! ($pos['ts'] !== null
            && $r->updated_at->format('Y-m-d H:i:s') === $pos['ts']
            && in_array($fingerprint($r), $pos['seen'], true)))->values();
    }

    private function position(array $pos, $fresh, callable $fingerprint): array
    {
        if ($fresh->isEmpty()) {
            return $pos;
        }

        $newest = $fresh->max(fn ($r) => $r->updated_at->format('Y-m-d H:i:s'));
        $seen = $fresh->filter(fn ($r) => $r->updated_at->format('Y-m-d H:i:s') === $newest)
            ->map($fingerprint)->values()->all();

        if ($newest === $pos['ts']) {
            $seen = array_values(array_unique(array_merge($pos['seen'], $seen)));
        }

        return ['ts' => $newest, 'seen' => $seen];
    }

    private function orderFingerprint(Order $o): string
    {
        return implode(':', ['o', $o->id, $o->status->value, $o->accepted_at ? 'a' : '-', $o->rejected_at ? 'r' : '-']);
    }

    private function requestFingerprint(BillRequest $r): string
    {
        return implode(':', ['b', $r->id, $r->status->value]);
    }

    // ── telemetry ───────────────────────────────────────────────────────

    private function stamp(PosTerminal $terminal, ?string $appVersion): void
    {
        $due = $terminal->last_feed_at === null
            || $terminal->last_feed_at->lt(now()->subSeconds(self::STAMP_EVERY_SECONDS));
        $versionChanged = $appVersion !== null && $appVersion !== '' && $appVersion !== $terminal->app_version;

        if (! $due && ! $versionChanged) {
            return;
        }

        $terminal->forceFill(array_filter([
            'last_feed_at' => now(),
            'app_version' => $versionChanged ? mb_substr($appVersion, 0, 32) : null,
        ]))->saveQuietly();
    }
}
