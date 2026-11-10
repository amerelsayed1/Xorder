<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreBranchRequest;
use App\Http\Requests\Dashboard\UpdateBranchEgressIpsRequest;
use App\Http\Requests\Dashboard\UpdateBranchRequest;
use App\Http\Resources\BranchResource;
use App\Models\Branch;
use App\Models\FinancialAccount;
use App\Models\PurchaseOrder;
use App\Models\Restaurant;
use App\Models\StockMovement;
use App\Models\SupplierInvoice;
use App\Models\SupplierPayment;
use App\Services\BranchEgressIpService;
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

    /**
     * GET branches/{branch}/presence — whether diners reach us from this
     * branch's own customer Wi-Fi, and how often.
     *
     * Read-only and observational: the signal never gates a session, so this is
     * reporting, not configuration. Tenant-scoped by RestaurantScope via the
     * route binding — another restaurant's branch id resolves to 404.
     */
    public function presence(Request $request, Branch $branch, BranchEgressIpService $egressIps): JsonResponse
    {
        return response()->json(['data' => $egressIps->stats($branch, $request->ip())]);
    }

    /**
     * PUT branches/{branch}/presence/egress-ips — declare this branch's customer
     * Wi-Fi address(es) by hand.
     *
     * The setup path for a branch with no history: learning needs several
     * geofence-verified scans before it can recognise a connection, which is a
     * poor first run when the owner is standing in the venue on that very
     * connection. Stored separately from the learned list so the nightly job
     * never overwrites what a person entered.
     */
    public function updateEgressIps(
        UpdateBranchEgressIpsRequest $request,
        Branch $branch,
        BranchEgressIpService $egressIps
    ): JsonResponse {
        $egressIps->setManualAddresses($branch, $request->validated('egress_ips'));

        return response()->json([
            'data' => $egressIps->stats($branch->fresh(), $request->ip()),
            'message' => __('xorder.messages.branch_updated'),
        ]);
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
        $data = $request->validated();

        // Stored in the till's spelling (`pickup` becomes `takeaway`), and only
        // when it actually changed: an unchanged list posted back by a form must
        // not rewrite what the Super Admin wizard stored, or bump the tills.
        unset($data['supported_order_types']);
        if ($request->changesOrderTypes()) {
            $data['supported_order_types'] = $request->requestedOrderTypes();
        }

        $branch->update($data);

        return response()->json([
            'data' => BranchResource::make($branch->fresh()),
            'message' => __('xorder.messages.branch_updated'),
        ]);
    }

    public function destroy(Branch $branch): JsonResponse
    {
        // CB-09: purchase orders, the stock ledger, supplier invoices and
        // supplier payments point at their branch with no cascade, on purpose
        // (what was bought, received, billed or paid at a branch is that
        // branch's history). Without this the FK would refuse the delete as
        // a 500; say why instead.
        if (PurchaseOrder::where('branch_id', $branch->id)->exists()
            || StockMovement::where('branch_id', $branch->id)->exists()
            || SupplierInvoice::where('branch_id', $branch->id)->exists()
            || SupplierPayment::where('branch_id', $branch->id)->exists()) {
            return response()->json(['message' => __('xorder.messages.branch_has_purchasing')], 409);
        }

        // XORD-015: a branch's own cash drawer or bank account points at it with
        // no cascade, on purpose (deleting the branch must not quietly turn the
        // account into one the whole business shares). Say why, as above.
        if (FinancialAccount::where('branch_id', $branch->id)->exists()) {
            return response()->json(['message' => __('xorder.messages.branch_has_accounts')], 409);
        }

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
