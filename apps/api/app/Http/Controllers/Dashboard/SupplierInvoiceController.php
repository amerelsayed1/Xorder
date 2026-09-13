<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreSupplierInvoiceRequest;
use App\Http\Requests\Dashboard\UpdateSupplierInvoiceRequest;
use App\Http\Requests\Dashboard\VoidSupplierInvoiceRequest;
use App\Http\Resources\SupplierInvoiceResource;
use App\Models\SupplierInvoice;
use App\Services\SupplierLedgerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice c: supplier invoices. Thin on purpose: create, edit and void
 * are SupplierLedgerService calls that lock the invoice row.
 *
 * RestaurantScope isolates the {supplierInvoice} binding (a foreign id is a
 * 404). There is no DELETE: an invoice entered in error is voided with a
 * reason, and stays on record.
 */
class SupplierInvoiceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'supplier_id' => ['nullable', 'integer'],
            'purchase_order_id' => ['nullable', 'integer'],
            'state' => ['nullable', 'in:open,overdue,settled,voided'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $today = $request->user()->restaurant->today();

        $page = SupplierInvoice::query()
            ->withPaid()
            ->with('branch')
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('supplier_id'), fn ($q) => $q->where('supplier_id', $request->integer('supplier_id')))
            ->when($request->filled('purchase_order_id'), fn ($q) => $q->where('purchase_order_id', $request->integer('purchase_order_id')))
            ->when($request->input('state') === 'open', fn ($q) => $q->open())
            ->when($request->input('state') === 'overdue', fn ($q) => $q->open($today))
            ->when($request->input('state') === 'settled', fn ($q) => $q->settled())
            ->when($request->input('state') === 'voided', fn ($q) => $q->whereNotNull('voided_at'))
            ->orderByDesc('issued_at')
            ->orderByDesc('id')
            ->paginate($request->integer('per_page') ?: 25);

        return SupplierInvoiceResource::collection($page)->response();
    }

    public function show(SupplierInvoice $supplierInvoice): JsonResponse
    {
        return $this->present($supplierInvoice);
    }

    public function store(StoreSupplierInvoiceRequest $request, SupplierLedgerService $ledger): JsonResponse
    {
        $invoice = $ledger->createInvoice($request->validated(), $request->user());

        return $this->present($invoice, __('xorder.messages.saved'), 201);
    }

    public function update(UpdateSupplierInvoiceRequest $request, SupplierInvoice $supplierInvoice, SupplierLedgerService $ledger): JsonResponse
    {
        $invoice = $ledger->updateInvoice($supplierInvoice, $request->validated(), $request->user());

        return $this->present($invoice, __('xorder.messages.saved'));
    }

    public function void(VoidSupplierInvoiceRequest $request, SupplierInvoice $supplierInvoice, SupplierLedgerService $ledger): JsonResponse
    {
        $invoice = $ledger->voidInvoice($supplierInvoice, $request->reason(), $request->validated('note'), $request->user());

        return $this->present($invoice, __('xorder.messages.saved'));
    }

    private function present(SupplierInvoice $invoice, ?string $message = null, int $status = 200): JsonResponse
    {
        $fresh = SupplierInvoice::query()
            ->withPaid()
            ->with(['lines', 'branch', 'supplier', 'purchaseOrder.lines', 'allocations.payment'])
            ->findOrFail($invoice->id);

        $body = ['data' => new SupplierInvoiceResource($fresh)];
        if ($message !== null) {
            $body['message'] = $message;
        }

        return response()->json($body, $status);
    }
}
