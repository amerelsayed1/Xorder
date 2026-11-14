<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\BillRequestStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\BillRequestResource;
use App\Models\BillRequest;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
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

        // Acting on a request (seen / in progress / completed / cancelled) means
        // it's no longer waiting — clear its unread "new bill request" alert so the
        // bell mirrors the board. The validation above never lets status fall back
        // to REQUESTED, so any update here is an acknowledgement. The bill_request_id
        // linkage is stored (as a string) on the notification's data payload by
        // PublicBillRequestController when the request is raised.
        Notification::query()
            ->where('type', 'bill_request.created')
            ->where('data->bill_request_id', (string) $bill->id)
            ->whereNull('read_at')
            ->update(['read_at' => Carbon::now()]);

        return response()->json([
            'data' => BillRequestResource::make($bill->fresh()->load(['table', 'diningArea'])),
            'message' => __('xorder.messages.bill_status_updated'),
        ]);
    }
}
