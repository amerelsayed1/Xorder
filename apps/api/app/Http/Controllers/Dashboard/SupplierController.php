<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreSupplierRequest;
use App\Http\Requests\Dashboard\UpdateSupplierRequest;
use App\Models\PurchaseOrder;
use App\Models\Supplier;
use App\Models\SupplierInvoice;
use App\Models\SupplierPayment;
use Illuminate\Http\JsonResponse;

/**
 * CB-09 slice a: suppliers. RestaurantScope isolates (a foreign id is a 404),
 * and the Auditable trait records every create and update.
 *
 * destroy deletes only a supplier nothing points at — one typed by mistake, or
 * one entered twice. The moment a purchase order, invoice or payment names it,
 * the row is part of what those documents mean, and the answer is to retire it
 * (is_active = false) rather than delete it. Those three tables hold a plain
 * FK with no cascade, so without the check the database would refuse the
 * delete as a 500; this says why instead. No balance is stored or returned
 * here; slice c derives one.
 */
class SupplierController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => Supplier::orderBy('id')->get()]);
    }

    public function show(Supplier $supplier): JsonResponse
    {
        return response()->json(['data' => $supplier]);
    }

    public function store(StoreSupplierRequest $request): JsonResponse
    {
        $supplier = new Supplier($request->validated());
        $supplier->forceFill(['updated_by' => $request->user()->id])->save();

        return response()->json(['data' => $supplier->fresh(), 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateSupplierRequest $request, Supplier $supplier): JsonResponse
    {
        $supplier->fill($request->validated())->forceFill(['updated_by' => $request->user()->id])->save();

        return response()->json(['data' => $supplier->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    public function destroy(Supplier $supplier): JsonResponse
    {
        if (PurchaseOrder::where('supplier_id', $supplier->id)->exists()
            || SupplierInvoice::where('supplier_id', $supplier->id)->exists()
            || SupplierPayment::where('supplier_id', $supplier->id)->exists()) {
            return response()->json(['message' => __('xorder.messages.supplier_has_purchasing')], 409);
        }

        $supplier->delete();

        return response()->json(['message' => __('xorder.messages.supplier_deleted')]);
    }
}
