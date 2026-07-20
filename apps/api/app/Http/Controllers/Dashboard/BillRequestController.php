<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\BillRequestStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\BillRequestResource;
use App\Models\BillRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class BillRequestController extends Controller
{
    /** Open requests (or a filtered/history slice) for the live board. */
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'status' => ['sometimes', Rule::in(BillRequestStatus::values())],
            'branch_id' => ['sometimes', 'integer'],
            'dining_area_id' => ['sometimes', 'integer'],
            'table_id' => ['sometimes', 'integer'],
        ]);

        $bills = BillRequest::with(['table', 'diningArea'])
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->when($request->filled('dining_area_id'), fn ($q) => $q->where('dining_area_id', $request->integer('dining_area_id')))
            ->when($request->filled('table_id'), fn ($q) => $q->where('table_id', $request->integer('table_id')))
            ->when(
                $request->filled('status'),
                fn ($q) => $q->where('status', $request->input('status')),
                // Default board view: everything still open, oldest first.
                fn ($q) => $q->whereIn('status', [
                    BillRequestStatus::REQUESTED->value,
                    BillRequestStatus::SEEN->value,
                    BillRequestStatus::IN_PROGRESS->value,
                ]),
            )
            ->orderBy('requested_at')
            ->get();

        return BillRequestResource::collection($bills)->response();
    }

    /** Lightweight badge for the dashboard nav: how many brand-new requests wait. */
    public function newCount(): JsonResponse
    {
        return response()->json([
            'count' => BillRequest::where('status', BillRequestStatus::REQUESTED->value)->count(),
        ]);
    }

    public function updateStatus(Request $request, BillRequest $bill): JsonResponse
    {
        $request->validate([
            'status' => ['required', Rule::in([
                BillRequestStatus::SEEN->value,
                BillRequestStatus::IN_PROGRESS->value,
                BillRequestStatus::COMPLETED->value,
                BillRequestStatus::CANCELLED->value,
            ])],
        ]);

        $status = $request->input('status');
        $userId = $request->user()?->id;

        switch ($status) {
            case BillRequestStatus::SEEN->value:
                if ($bill->seen_at === null) {
                    $bill->seen_at = now();
                    $bill->seen_by = $userId;
                }
                break;
            case BillRequestStatus::IN_PROGRESS->value:
                if ($bill->seen_at === null) {
                    $bill->seen_at = now();
                    $bill->seen_by = $userId;
                }
                $bill->started_at ??= now();
                break;
            case BillRequestStatus::COMPLETED->value:
                $bill->completed_at = now();
                $bill->completed_by = $userId;
                break;
            case BillRequestStatus::CANCELLED->value:
                $bill->cancelled_at = now();
                break;
        }

        $bill->status = $status;
        $bill->save();

        return response()->json([
            'data' => BillRequestResource::make($bill->fresh()->load(['table', 'diningArea'])),
            'message' => __('xorder.messages.bill_status_updated'),
        ]);
    }
}
