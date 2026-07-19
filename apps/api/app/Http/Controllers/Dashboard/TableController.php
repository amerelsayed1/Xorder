<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreTableRequest;
use App\Http\Requests\Dashboard\UpdateTableRequest;
use App\Http\Resources\DiningTableResource;
use App\Models\DiningArea;
use App\Models\DiningTable;
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
