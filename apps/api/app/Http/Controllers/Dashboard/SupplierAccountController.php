<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Supplier;
use App\Services\SupplierAccountService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice c: what each supplier is owed, DERIVED on every read from the
 * live invoices and payments (SupplierAccountService). Nothing is stored.
 *
 * `as_of` (default: the business's own today) decides what is overdue: an
 * invoice is late only once as-of is after its due date.
 */
class SupplierAccountController extends Controller
{
    public function account(Request $request, Supplier $supplier, SupplierAccountService $accounts): JsonResponse
    {
        $request->validate([
            'branch_id' => ['nullable', 'integer'],
            'as_of' => ['nullable', 'date_format:Y-m-d'],
        ]);
        $restaurant = $request->user()->restaurant;
        $asOf = $request->input('as_of') ?: $restaurant->today();

        return response()->json(['data' => [
            'supplier' => [
                'id' => $supplier->id,
                'name_en' => $supplier->name_en,
                'name_ar' => $supplier->name_ar,
                'code' => $supplier->code,
                'phone' => $supplier->phone,
                'payment_term_days' => $supplier->payment_term_days,
                'is_active' => $supplier->is_active,
            ],
            'as_of' => $asOf,
            'currency' => $restaurant->currency?->value,
            'exponent' => $restaurant->currency?->exponent() ?? 2,
        ] + $accounts->account($supplier, $request->integer('branch_id') ?: null, $asOf)]);
    }

    public function balances(Request $request, SupplierAccountService $accounts): JsonResponse
    {
        $request->validate(['branch_id' => ['nullable', 'integer']]);
        $restaurant = $request->user()->restaurant;
        $asOf = $restaurant->today();

        $rows = [];
        foreach ($accounts->balances($restaurant->id, $request->integer('branch_id') ?: null, $asOf) as $supplierId => $figures) {
            $rows[] = ['supplier_id' => $supplierId] + $figures;
        }

        return response()->json([
            'data' => $rows,
            'meta' => [
                'as_of' => $asOf,
                'currency' => $restaurant->currency?->value,
                'exponent' => $restaurant->currency?->exponent() ?? 2,
            ],
        ]);
    }
}
