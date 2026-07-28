<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\BulkDeleteTablesRequest;
use App\Http\Requests\Dashboard\StoreTableRequest;
use App\Http\Requests\Dashboard\UpdateTableRequest;
use App\Http\Resources\DiningTableResource;
use App\Models\BillRequest;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Order;
use App\Services\QrCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class TableController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $tables = DiningTable::with('diningArea')
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('dining_area_id'), fn ($q) => $q->where('dining_area_id', $request->integer('dining_area_id')))
            ->when($request->input('status') === 'active', fn ($q) => $q->where('is_active', true))
            ->when($request->input('status') === 'inactive', fn ($q) => $q->where('is_active', false))
            ->when($request->filled('search'), fn ($q) => $q->where('label', 'like', '%'.$request->string('search').'%'))
            ->orderBy('dining_area_id')->orderBy('label')
            ->get();

        return DiningTableResource::collection($tables)->response();
    }

    /**
     * Live floor grid for the dashboard: every active table with its current
     * occupancy, active-order count, and whether it has an open bill request
     * (which makes the card pulse for attention). Kept light — a handful of
     * grouped queries, no per-table N+1. Tenant scoping is applied by the
     * BelongsToRestaurant global scope on each model.
     */
    public function live(Request $request): JsonResponse
    {
        $tables = DiningTable::with('diningArea')
            ->where('is_active', true)
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('dining_area_id'), fn ($q) => $q->where('dining_area_id', $request->integer('dining_area_id')))
            ->orderBy('dining_area_id')->orderBy('label')
            ->get();

        $tableIds = $tables->pluck('id');

        // Occupancy signal: a live (non-expired) menu session on the table.
        $occupied = MenuSession::whereIn('table_id', $tableIds)
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()))
            ->pluck('table_id')->flip();

        // Active orders per table (still NEW — completed/cancelled ones drop out).
        $activeOrders = Order::whereIn('table_id', $tableIds)
            ->where('status', OrderStatus::NEW->value)
            ->selectRaw('table_id, count(*) as c')->groupBy('table_id')
            ->pluck('c', 'table_id');

        // Tables with a freshly-placed (NEW) order → they flash for attention.
        $newOrders = Order::whereIn('table_id', $tableIds)
            ->where('status', OrderStatus::NEW->value)
            ->pluck('table_id')->flip();

        // Tables with an open bill request → they pulse.
        $openRequests = BillRequest::whereIn('table_id', $tableIds)
            ->whereIn('status', [
                BillRequestStatus::REQUESTED->value,
                BillRequestStatus::SEEN->value,
                BillRequestStatus::IN_PROGRESS->value,
            ])->pluck('table_id')->flip();

        $data = $tables->map(function ($t) use ($occupied, $activeOrders, $openRequests, $newOrders) {
            $orders = (int) ($activeOrders[$t->id] ?? 0);

            return [
                'id' => $t->id,
                'label' => $t->label,
                'dining_area_id' => $t->dining_area_id,
                'area_name_en' => $t->diningArea?->name_en,
                'area_name_ar' => $t->diningArea?->name_ar,
                'active_orders' => $orders,
                'has_request' => $openRequests->has($t->id),
                // A new order that staff hasn't acknowledged yet → flash the card.
                'has_new_order' => $newOrders->has($t->id),
                // Occupied if a guest session is live or there are active orders.
                'occupied' => $occupied->has($t->id) || $orders > 0,
            ];
        });

        return response()->json(['data' => $data]);
    }

    public function store(StoreTableRequest $request): JsonResponse
    {
        $area = DiningArea::findOrFail($request->integer('dining_area_id'));

        $table = new DiningTable($request->validated());
        // Branch is derived from the area so the two can never disagree.
        $table->branch_id = $area->branch_id;
        $table->public_token = DiningTable::generateToken();
        $table->qr_generated_at = now();
        $table->save();

        return response()->json([
            'data' => DiningTableResource::make($table->load('diningArea')),
            'message' => __('xorder.messages.table_created'),
        ], 201);
    }

    public function update(UpdateTableRequest $request, DiningTable $table): JsonResponse
    {
        $table->fill($request->validated());
        if ($table->isDirty('dining_area_id')) {
            $table->branch_id = DiningArea::findOrFail($table->dining_area_id)->branch_id;
        }
        $table->save();

        return response()->json([
            'data' => DiningTableResource::make($table->fresh()->load('diningArea')),
            'message' => __('xorder.messages.table_updated'),
        ]);
    }

    public function toggleStatus(Request $request, DiningTable $table): JsonResponse
    {
        $request->validate(['is_active' => ['sometimes', 'boolean']]);

        $table->is_active = $request->has('is_active')
            ? $request->boolean('is_active')
            : ! $table->is_active;
        $table->save();

        return response()->json([
            'data' => DiningTableResource::make($table->load('diningArea')),
            'message' => __('xorder.messages.table_status_updated'),
        ]);
    }

    public function destroy(DiningTable $table): JsonResponse
    {
        if ($table->orders()->exists()) {
            return response()->json(['message' => __('xorder.messages.table_has_history')], 409);
        }

        $table->delete();

        return response()->json(['message' => __('xorder.messages.table_deleted')]);
    }

    /**
     * Delete several tables at once. Tables with order history are kept (same
     * rule as the single delete) and reported back as skipped. The tenant
     * scope limits the query to the caller's own tables.
     */
    public function bulkDestroy(BulkDeleteTablesRequest $request): JsonResponse
    {
        $ids = collect($request->validated('ids'))->unique();
        $tables = DiningTable::whereIn('id', $ids)->get();

        $deleted = 0;
        $skipped = 0;
        foreach ($tables as $table) {
            if ($table->orders()->exists()) {
                $skipped++;

                continue;
            }
            $table->delete();
            $deleted++;
        }

        $message = $skipped === 0
            ? trans_choice('xorder.messages.tables_deleted', $deleted, ['count' => $deleted])
            : __('xorder.messages.tables_deleted_partial', ['deleted' => $deleted, 'skipped' => $skipped]);

        return response()->json([
            'deleted' => $deleted,
            'skipped' => $skipped,
            'message' => $message,
        ]);
    }

    /** SVG preview + the URL the QR encodes. */
    public function qr(DiningTable $table, QrCodeService $qr): JsonResponse
    {
        $url = $table->publicUrl();

        return response()->json([
            'data' => [
                'svg' => $qr->svgForUrl($url),
                'url' => $url,
                'public_token' => $table->public_token,
                'qr_generated_at' => $table->qr_generated_at,
            ],
        ]);
    }

    public function qrDownload(DiningTable $table, QrCodeService $qr): Response
    {
        return response($qr->pngForUrl($table->publicUrl()))
            ->header('Content-Type', 'image/png')
            ->header('Content-Disposition', 'attachment; filename="'.$qr->tableDownloadFilename($table).'"');
    }

    /** Issue a fresh token; the previous QR stops resolving (FR-QR-007/008). */
    public function regenerateQr(DiningTable $table): JsonResponse
    {
        $table->public_token = DiningTable::generateToken();
        $table->qr_generated_at = now();
        $table->save();

        return response()->json([
            'data' => DiningTableResource::make($table->load('diningArea')),
            'message' => __('xorder.messages.qr_regenerated'),
        ]);
    }
}
