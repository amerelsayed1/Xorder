<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\PurchaseStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ReceivePurchaseOrderRequest;
use App\Http\Requests\Dashboard\StorePurchaseOrderRequest;
use App\Http\Requests\Dashboard\UpdatePurchaseOrderRequest;
use App\Http\Resources\PurchaseOrderResource;
use App\Models\PurchaseOrder;
use App\Services\PurchaseOrderService;
use App\Services\ReceivingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * CB-09 slice b: purchase orders. Thin on purpose: every transition (edit,
 * send, cancel, receive) is a service call that locks the order row and
 * re-reads its status under the lock, so a stale page can never cancel an
 * order that has had goods booked in since it was loaded.
 *
 * RestaurantScope isolates the {purchaseOrder} binding (a foreign id is a
 * 404). There is no DELETE: a draft that isn't wanted is cancelled.
 */
class PurchaseOrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'supplier_id' => ['nullable', 'integer'],
            'status' => ['nullable', Rule::enum(PurchaseStatus::class)],
        ]);

        $page = PurchaseOrder::query()
            ->with(['lines', 'branch'])
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('supplier_id'), fn ($q) => $q->where('supplier_id', $request->integer('supplier_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')->value()))
            ->orderByDesc('id')
            ->paginate(25);

        return PurchaseOrderResource::collection($page)->response();
    }

    public function show(PurchaseOrder $purchaseOrder): JsonResponse
    {
        return $this->present($purchaseOrder);
    }

    public function store(StorePurchaseOrderRequest $request, PurchaseOrderService $orders): JsonResponse
    {
        $order = $orders->create($request->validated(), $request->user());

        return $this->present($order, __('xorder.messages.saved'), 201);
    }

    public function update(UpdatePurchaseOrderRequest $request, PurchaseOrder $purchaseOrder, PurchaseOrderService $orders): JsonResponse
    {
        $order = $orders->update($purchaseOrder, $request->validated(), $request->user());

        return $this->present($order, __('xorder.messages.saved'));
    }

    public function send(Request $request, PurchaseOrder $purchaseOrder, PurchaseOrderService $orders): JsonResponse
    {
        return $this->present($orders->send($purchaseOrder, $request->user()), __('xorder.messages.saved'));
    }

    public function cancel(Request $request, PurchaseOrder $purchaseOrder, PurchaseOrderService $orders): JsonResponse
    {
        return $this->present($orders->cancel($purchaseOrder, $request->user()), __('xorder.messages.saved'));
    }

    public function receive(ReceivePurchaseOrderRequest $request, PurchaseOrder $purchaseOrder, ReceivingService $receiving): JsonResponse
    {
        $occurredAt = $request->validated('occurred_at');

        $order = $receiving->receive(
            $purchaseOrder,
            $request->quantities(),
            $occurredAt ? Carbon::parse($occurredAt) : null,
            $request->validated('note'),
            $request->user(),
        );

        return $this->present($order, __('xorder.messages.saved'));
    }

    private function present(PurchaseOrder $order, ?string $message = null, int $status = 200): JsonResponse
    {
        $fresh = PurchaseOrder::query()
            ->with(['lines.stockItem', 'branch', 'supplier'])
            ->findOrFail($order->id);

        $body = ['data' => new PurchaseOrderResource($fresh)];
        if ($message !== null) {
            $body['message'] = $message;
        }

        return response()->json($body, $status);
    }
}
