<?php

namespace App\Http\Controllers\Pos;

use App\Http\Controllers\Controller;
use App\Http\Requests\Pos\StoreRefundRequest;
use App\Http\Resources\PosRefundResource;
use App\Models\PosRefund;
use App\Models\PosTerminal;
use App\Services\PosRefundService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-010: money back, as a reversing record.
 *
 * Idempotency to the letter of POS-BE-007: a replay serialises the STORED
 * refund through the same resource, so every submission of one key gets the
 * same body — credit note number included — and a replay is never 409.
 */
class RefundController extends Controller
{
    public function __construct(private readonly PosRefundService $service) {}

    public function store(StoreRefundRequest $request): JsonResponse
    {
        /** @var PosTerminal $terminal */
        $terminal = $request->attributes->get('pos_terminal');

        ['refund' => $refund, 'replay' => $replay] = $this->service->create($terminal, $request->validated());

        return response()->json(
            ['data' => PosRefundResource::make($this->hydrate($refund))],
            $replay ? 200 : 201,
        );
    }

    /**
     * POS-BE-007's recovery lookup, the refund half: a till that lost the
     * response learns the record's id and credit note number — the state the
     * key exists to make recoverable.
     */
    public function byClientId(Request $request, string $uuid): JsonResponse
    {
        $refund = PosRefund::where('client_transaction_id', $uuid)->first();

        if ($refund === null) {
            return response()->json([
                'code' => 'VALIDATION_FAILED',
                'message' => __('xorder.messages.refund_not_found'),
            ], 404);
        }

        return response()->json(['data' => PosRefundResource::make($this->hydrate($refund))]);
    }

    private function hydrate(PosRefund $refund): PosRefund
    {
        // The order's payments are loaded because settlement_status is derived
        // from them on every read, never stored.
        return $refund->load(['lines.orderItem', 'tenders', 'order.payments']);
    }
}
