<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Resources\CustomerResource;
use App\Http\Resources\OrderResource;
use App\Models\Customer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $customers = Customer::query()
            ->withCount(['orders', 'addresses'])
            ->when($request->filled('search'), function ($q) use ($request) {
                $term = '%'.$request->string('search').'%';
                $q->where(fn ($q) => $q->where('name', 'like', $term)->orWhere('phone', 'like', $term)->orWhere('email', 'like', $term));
            })
            ->orderByDesc('id')
            ->paginate(20);

        return CustomerResource::collection($customers)->response();
    }

    public function show(Customer $customer): JsonResponse
    {
        // Route-model binding is tenant-scoped by the global RestaurantScope.
        $customer->load('addresses')->loadCount('orders');
        $recent = $customer->orders()->with('customerAddress')->latest()->limit(25)->get();

        return response()->json([
            'data' => new CustomerResource($customer),
            'recent_orders' => OrderResource::collection($recent),
        ]);
    }
}
