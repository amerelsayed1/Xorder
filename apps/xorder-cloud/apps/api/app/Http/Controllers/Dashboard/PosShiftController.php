<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ForceCloseShiftRequest;
use App\Models\PosShift;
use App\Services\PosShiftService;
use Illuminate\Http\JsonResponse;

/**
 * dashboard-shift-details: one shift as the back office sees it, and the
 * force close for a shift whose till was revoked before closing it.
 *
 * Tenant-scoped by route binding (`BelongsToRestaurant`): another tenant's
 * shift id is a 404. The figures are PosShiftService::summary(), the same
 * numbers the till's own report key prints.
 */
class PosShiftController extends Controller
{
    public function __construct(private readonly PosShiftService $shifts) {}

    public function show(PosShift $shift): JsonResponse
    {
        return response()->json(['data' => $this->present($shift)]);
    }

    public function forceClose(ForceCloseShiftRequest $request, PosShift $shift): JsonResponse
    {
        $closed = $this->shifts->forceClose(
            $shift,
            $request->user(),
            (int) $request->validated('counted_cash_minor'),
            trim($request->validated('reason')),
        );

        return response()->json([
            'message' => __('xorder.messages.pos_shift_force_closed'),
            'data' => $this->present($closed),
        ]);
    }

    /** @return array<string,mixed> */
    private function present(PosShift $shift): array
    {
        $shift->loadMissing(['terminal', 'openedBy', 'closedBy', 'branch']);
        $summary = $this->shifts->summary($shift);
        $terminalRevoked = (bool) $shift->terminal?->isRevoked();

        return [
            'id' => $shift->id,
            'status' => $shift->status,
            // null = closed at the till; 'dashboard' = force-closed here.
            'closed_via' => $shift->closed_via,
            'branch' => $shift->branch ? [
                'id' => $shift->branch->id,
                'name_ar' => $shift->branch->name_ar,
                'name_en' => $shift->branch->name_en,
            ] : null,
            'terminal' => $shift->terminal ? [
                'id' => $shift->terminal->id,
                'name' => $shift->terminal->name,
                'revoked' => $terminalRevoked,
            ] : null,
            'opened_by' => $shift->openedBy?->name,
            'closed_by' => $shift->closedBy?->name,
            'opened_at' => $shift->opened_at?->toIso8601String(),
            'closed_at' => $shift->closed_at?->toIso8601String(),
            'opening_float_minor' => (int) $shift->opening_float_minor,
            'counted_cash_minor' => $shift->counted_cash_minor,
            'expected_cash_minor' => $summary['expected_cash_minor'],
            'variance_minor' => $shift->variance_minor,
            'variance_reason' => $shift->variance_reason,
            // A hint for the page; the server re-checks both under a lock.
            'can_force_close' => $shift->isOpen() && $terminalRevoked,
            'summary' => [
                'orders_count' => $summary['orders_count'],
                'sales_minor' => array_sum(array_column($summary['sales_by_tender'], 'amount_minor')),
                'sales_by_tender' => $summary['sales_by_tender'],
                'cash_in_minor' => $summary['cash_in_minor'],
                'cash_out_minor' => $summary['cash_out_minor'],
                'refunds_minor' => $summary['refunds_minor'],
                'refunds_count' => $summary['refunds_count'],
                'cash_refunds_minor' => $summary['cash_refunds_minor'],
            ],
            'orders' => $shift->orders()->latest('id')->get()->map(fn ($order) => [
                'id' => $order->id,
                'code' => $order->code(),
                'invoice_number' => $order->invoice_number,
                'status' => $order->status->value,
                'total_minor' => $order->total_minor,
                'created_at' => $order->created_at?->toIso8601String(),
            ])->all(),
            'cash_movements' => $shift->cashMovements()->orderBy('occurred_at')->get()->map(fn ($m) => [
                'id' => $m->id,
                'direction' => $m->direction,
                'amount_minor' => (int) $m->amount_minor,
                'reason' => $m->reason,
                'occurred_at' => $m->occurred_at?->toIso8601String(),
            ])->all(),
        ];
    }
}
