<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreSupplierPaymentRequest;
use App\Http\Requests\Dashboard\VoidSupplierPaymentRequest;
use App\Http\Resources\SupplierPaymentResource;
use App\Models\PosCashMovement;
use App\Models\SupplierPayment;
use App\Services\SupplierLedgerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice c: supplier payments. Recording one (with its allocations) and
 * voiding one are SupplierLedgerService calls under row locks. There is no
 * update and no DELETE: a wrong payment is voided with a reason and entered
 * again, which gives the room it took on each invoice back.
 *
 * RestaurantScope isolates the {supplierPayment} binding (a foreign id is a 404).
 */
class SupplierPaymentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'supplier_id' => ['nullable', 'integer'],
            'state' => ['nullable', 'in:live,voided'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        $page = SupplierPayment::query()
            ->withSum('allocations', 'amount_minor')
            ->with('branch')
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('supplier_id'), fn ($q) => $q->where('supplier_id', $request->integer('supplier_id')))
            ->when($request->input('state') === 'live', fn ($q) => $q->whereNull('voided_at'))
            ->when($request->input('state') === 'voided', fn ($q) => $q->whereNotNull('voided_at'))
            ->orderByDesc('paid_at')
            ->orderByDesc('id')
            ->paginate($request->integer('per_page') ?: 25);

        return SupplierPaymentResource::collection($page)->response();
    }

    public function show(SupplierPayment $supplierPayment): JsonResponse
    {
        return $this->present($supplierPayment);
    }

    public function store(StoreSupplierPaymentRequest $request, SupplierLedgerService $ledger): JsonResponse
    {
        $payment = $ledger->pay($request->validated(), $request->user());

        return $this->present($payment, __('xorder.messages.saved'), 201);
    }

    public function void(VoidSupplierPaymentRequest $request, SupplierPayment $supplierPayment, SupplierLedgerService $ledger): JsonResponse
    {
        $payment = $ledger->voidPayment($supplierPayment, $request->reason(), $request->validated('note'), $request->user());

        return $this->present($payment, __('xorder.messages.saved'));
    }

    /**
     * Design D13: till pay-outs (synced POS cash movements, direction out)
     * not yet linked to a live payment, newest first, as candidates for "this
     * payment came out of the drawer". A client without a till simply has
     * none. Read-only: the till still authors every movement.
     */
    public function drawerPayouts(Request $request): JsonResponse
    {
        $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'amount_minor' => ['nullable', 'integer', 'min:1'],
        ]);

        $linked = SupplierPayment::query()->whereNotNull('drawer_link_key')->select('drawer_link_key');

        $rows = PosCashMovement::query()
            ->where('direction', 'out')
            ->whereNotIn('id', $linked)
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('amount_minor'), fn ($q) => $q->where('amount_minor', $request->integer('amount_minor')))
            ->orderByDesc('occurred_at')
            ->orderByDesc('id')
            ->limit(50)
            ->get(['id', 'branch_id', 'amount_minor', 'reason', 'reference', 'occurred_at']);

        return response()->json(['data' => $rows->map(fn (PosCashMovement $m) => [
            'id' => $m->id,
            'branch_id' => (int) $m->branch_id,
            'amount_minor' => (int) $m->amount_minor,
            'reason' => $m->reason,
            'reference' => $m->reference,
            'occurred_at' => $m->occurred_at?->toIso8601String(),
        ])->values()]);
    }

    private function present(SupplierPayment $payment, ?string $message = null, int $status = 200): JsonResponse
    {
        $fresh = SupplierPayment::query()
            ->with(['allocations.invoice', 'branch', 'cashMovement'])
            ->findOrFail($payment->id);

        $body = ['data' => new SupplierPaymentResource($fresh)];
        if ($message !== null) {
            $body['message'] = $message;
        }

        return response()->json($body, $status);
    }
}
