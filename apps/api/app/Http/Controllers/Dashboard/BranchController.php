<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreBranchRequest;
use App\Http\Requests\Dashboard\UpdateBranchRequest;
use App\Http\Resources\BranchResource;
use App\Models\Branch;
use App\Models\Restaurant;
use App\Services\PlanLimitService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BranchController extends Controller
{
    public function index(): JsonResponse
    {
        $branches = Branch::orderBy('sort_order')->orderBy('id')->get();

        return BranchResource::collection($branches)->response();
    }

    public function store(StoreBranchRequest $request, PlanLimitService $limits): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        // Serialize the limit check + insert per tenant. Without the row lock,
        // N concurrent POSTs all read count < max before any commits and every
        // one succeeds, over-provisioning past the paid plan limit (TOCTOU).
        $result = DB::transaction(function () use ($restaurant, $limits, $request) {
            Restaurant::whereKey($restaurant->getKey())->lockForUpdate()->first();

            if (($limit = $limits->branchLimitReached($restaurant)) !== null) {
                return ['limit' => $limit];
            }

            // restaurant_id is stamped by the BelongsToRestaurant trait.
            return ['branch' => Branch::create($request->validated())];
        });

        if (isset($result['limit'])) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_branches', ['limit' => $result['limit']]),
            ], 422);
        }

        return response()->json([
            'data' => BranchResource::make($result['branch']),
            'message' => __('xorder.messages.branch_created'),
        ], 201);
    }

    public function update(UpdateBranchRequest $request, Branch $branch): JsonResponse
    {
        $branch->update($request->validated());

        return response()->json([
            'data' => BranchResource::make($branch->fresh()),
            'message' => __('xorder.messages.branch_updated'),
        ]);
    }

    public function destroy(Branch $branch): JsonResponse
    {
        $branch->delete();

        return response()->json(['message' => __('xorder.messages.branch_deleted')]);
    }

    /** PATCH open/closed: set is_open explicitly, or toggle when omitted. */
    public function toggleOpen(Request $request, Branch $branch): JsonResponse
    {
        $request->validate(['is_open' => ['sometimes', 'boolean']]);

        $branch->is_open = $request->has('is_open')
            ? $request->boolean('is_open')
            : ! $branch->is_open;
        $branch->save();

        return response()->json([
            'data' => BranchResource::make($branch),
            'message' => __('xorder.messages.branch_updated'),
        ]);
    }
}
