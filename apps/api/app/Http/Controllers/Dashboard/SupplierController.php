<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreSupplierRequest;
use App\Http\Requests\Dashboard\UpdateSupplierRequest;
use App\Models\Supplier;
use Illuminate\Http\JsonResponse;

/**
 * CB-09 slice a: suppliers. RestaurantScope isolates (a foreign id is a 404),
 * and the Auditable trait records every create and update.
 *
 * No destroy: a supplier is retired with is_active = false, because purchase
 * orders, invoices and payments (slices b and c) will reference it. No
 * balance is stored or returned here; slice c derives one.
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
}
