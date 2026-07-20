<?php

namespace App\Http\Controllers\Public;

use App\Enums\BillRequestStatus;
use App\Http\Controllers\Controller;
use App\Models\BillRequest;
use App\Models\MenuSession;
use App\Services\PushService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Customer-facing bill requests raised from a table QR session. The customer
 * holds an opaque request token to poll status and cancel while still pending.
 */
class PublicBillRequestController extends Controller
{
    /** POST /public/sessions/{sessionToken}/bill-requests */
    public function store(Request $request, string $sessionToken, PushService $push): JsonResponse
    {
        $request->validate([
            'note' => ['nullable', 'string', 'max:500'],
            'phone' => ['nullable', 'string', 'max:32'],
        ]);

        $session = $this->resolveSession($sessionToken);

        $latest = BillRequest::withoutGlobalScopes()
            ->where('menu_session_id', $session->id)
            ->latest('id')
            ->first();

        // Already an open request → surface it instead of duplicating (FR-BILL-010).
        if ($latest && $latest->isOpen()) {
            return response()->json([
                'data' => $this->present($latest),
                'duplicate' => true,
                'message' => __('xorder.messages.bill_request_active'),
            ], 200);
        }

        // Cooldown after a finished/cancelled one (FR-BILL-009).
        $cooldown = (int) config('platform.bill_request_cooldown_seconds', 120);
        if ($latest && $latest->created_at->gt(now()->subSeconds($cooldown))) {
            return response()->json([
                'data' => $this->present($latest),
                'cooldown' => true,
                'message' => __('xorder.messages.bill_request_active'),
            ], 200);
        }

        $bill = new BillRequest([
            'branch_id' => $session->branch_id,
            'dining_area_id' => $session->dining_area_id,
            'table_id' => $session->table_id,
            'menu_session_id' => $session->id,
            'public_token' => BillRequest::generateToken(),
            'status' => BillRequestStatus::REQUESTED->value,
            'customer_note' => $request->input('note'),
            'customer_phone' => $request->input('phone'),
            'requested_at' => now(),
        ]);
        $bill->restaurant_id = $session->restaurant_id;
        $bill->save();

        $session->forceFill(['last_activity_at' => now()])->save();

        // Notify the restaurant's devices after the response is flushed.
        $restaurantId = $session->restaurant_id;
        $lang = $session->restaurant->default_language->value;
        $label = $session->table?->label;
        app()->terminating(function () use ($push, $restaurantId, $label, $lang) {
            $push->newBillRequestToRestaurant(
                $restaurantId,
                __('xorder.messages.push_bill_request_title', [], $lang),
                __('xorder.messages.push_bill_request_body', ['table' => $label ?? '-'], $lang),
            );
        });

        return response()->json([
            'data' => $this->present($bill),
            'message' => __('xorder.messages.bill_request_created'),
        ], 201);
    }

    /** GET /public/bill-requests/{token} */
    public function show(string $token): JsonResponse
    {
        return response()->json(['data' => $this->present($this->resolveRequest($token))]);
    }

    /** PATCH /public/bill-requests/{token}/cancel — only while still Requested. */
    public function cancel(string $token): JsonResponse
    {
        $bill = $this->resolveRequest($token);

        if ($bill->status !== BillRequestStatus::REQUESTED) {
            return response()->json(['message' => __('xorder.messages.bill_cannot_cancel')], 422);
        }

        $bill->forceFill([
            'status' => BillRequestStatus::CANCELLED->value,
            'cancelled_at' => now(),
        ])->save();

        return response()->json([
            'data' => $this->present($bill),
            'message' => __('xorder.messages.bill_cancelled'),
        ]);
    }

    private function resolveSession(string $sessionToken): MenuSession
    {
        $session = MenuSession::withoutGlobalScopes()
            ->with(['restaurant.features', 'table', 'branch'])
            ->where('session_token', $sessionToken)
            ->first();

        if ($session === null) {
            abort(404, __('xorder.messages.session_expired'));
        }
        if (! $session->restaurant->isPubliclyVisible() || ! $session->restaurant->hasFeature('bill_requests')) {
            abort(403, __('xorder.errors.feature_disabled'));
        }
        if ($session->table && ! $session->table->is_active) {
            abort(403, __('xorder.messages.table_disabled'));
        }
        if ($session->branch && ! $session->branch->is_active) {
            abort(403, __('xorder.messages.branch_disabled'));
        }

        return $session;
    }

    private function resolveRequest(string $token): BillRequest
    {
        $bill = BillRequest::withoutGlobalScopes()->with('table')->where('public_token', $token)->first();

        if ($bill === null) {
            abort(404, __('xorder.messages.bill_request_not_found'));
        }

        return $bill;
    }

    /** @return array<string,mixed> */
    private function present(BillRequest $bill): array
    {
        return [
            'token' => $bill->public_token,
            'status' => $bill->status->value,
            'table' => $bill->table ? ['label' => $bill->table->label] : null,
            'requested_at' => $bill->requested_at,
            'seen_at' => $bill->seen_at,
            'completed_at' => $bill->completed_at,
            'cancelled_at' => $bill->cancelled_at,
        ];
    }
}
