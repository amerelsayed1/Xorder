<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\StoreOrderPaymentRequest;
use App\Http\Requests\Pos\StorePosOrderRequest;
use App\Http\Resources\PosOrderResource;
use App\Models\Order;
use App\Models\PosTerminal;
use App\Services\PagerSessionService;
use App\Services\PosOrderService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-006 (+ §006-P): server-priced order creation and later settlement.
 *
 * Idempotency to the letter of POS-BE-007: a replay serialises the STORED
 * order through the same resource, so all five submissions of one key get the
 * same body — id and invoice number included — and a replay is never 409.
 */
class OrderController extends Controller
{
    public function __construct(private readonly PosOrderService $service) {}

    public function store(StorePosOrderRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        $data = $request->validated();
        $pagerCode = $data['pager_code'] ?? null;
        unset($data['pager_code']);

        ['order' => $order, 'replay' => $replay] = $this->service->create($terminal, $data);

        $body = ['data' => PosOrderResource::make($order->load(['orderItems', 'payments']))];

        // Guest paging, shared QR (POS-BE-035). Bound after the order is stored,
        // on a replay too (a retry whose first attempt died before binding
        // finishes the job). Best effort: the order's own result never changes,
        // and the answer is information for the till, not an error.
        if ($pagerCode !== null && $pagerCode !== '') {
            $body['pager'] = ['status' => app(PagerSessionService::class)->bind($terminal->restaurant, $order, $pagerCode)];
        }

        return response()->json($body, $replay ? 200 : 201);
    }

    /** §006-P — {order} accepts the server id or the order's client uuid. */
    public function storePayment(StoreOrderPaymentRequest $request, string $order): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['payment' => $payment, 'order' => $resolved, 'replay' => $replay] =
            $this->service->addPayment($terminal, $order, $request->validated());

        return response()->json([
            'data' => [
                'id' => $payment->id,
                'client_transaction_id' => $payment->client_transaction_id,
                'tender_type_id' => $payment->tender_type_id,
                'amount_minor' => (int) $payment->amount_minor,
                'order_id' => $resolved->id,
                'settlement_status' => $this->service->settlementStatus($resolved),
            ],
        ], $replay ? 200 : 201);
    }

    /**
     * POS-BE-007's recovery lookup: a client that lost the response learns the
     * record's id — which is precisely the state the key exists to prevent.
     */
    public function byClientId(Request $request, string $uuid): JsonResponse
    {
        $order = Order::where('channel', 'pos')
            ->where('client_transaction_id', $uuid)
            ->first();

        if ($order === null) {
            return response()->json([
                'code' => 'VALIDATION_FAILED',
                'message' => __('xorder.messages.order_not_found'),
            ], 404);
        }

        return response()->json(['data' => PosOrderResource::make($order->load(['orderItems', 'payments']))]);
    }
}
