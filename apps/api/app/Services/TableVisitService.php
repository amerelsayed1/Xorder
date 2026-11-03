<?php

namespace App\Services;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Enums\TableVisitStatus;
use App\Models\BillRequest;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Order;
use App\Models\TableVisit;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class TableVisitService
{
    /** Must be called inside a transaction. Locking the table serializes scans. */
    public function activeForTable(DiningTable $table): TableVisit
    {
        DiningTable::withoutGlobalScopes()->whereKey($table->id)->lockForUpdate()->firstOrFail();

        $visit = TableVisit::withoutGlobalScopes()
            ->where('table_id', $table->id)
            ->where('status', TableVisitStatus::OPEN->value)
            ->latest('id')
            ->first();

        if ($visit !== null) {
            $ttl = (int) config('platform.table_session_ttl_minutes', 240);
            if ($visit->opened_at->gt(now()->subMinutes($ttl))) {
                return $visit;
            }

            $this->expire($visit);
        }

        $visit = new TableVisit([
            'branch_id' => $table->branch_id,
            'dining_area_id' => $table->dining_area_id,
            'table_id' => $table->id,
            'status' => TableVisitStatus::OPEN->value,
            'opened_at' => now(),
        ]);
        $visit->restaurant_id = $table->restaurant_id;
        $visit->save();

        return $visit;
    }

    /** Close a forgotten visit at its absolute TTL before admitting a new party. */
    private function expire(TableVisit $visit): void
    {
        Order::withoutGlobalScopes()
            ->where('table_visit_id', $visit->id)
            ->where('status', OrderStatus::NEW->value)
            ->update(['status' => OrderStatus::COMPLETED->value, 'updated_at' => now()]);

        $sessionIds = MenuSession::withoutGlobalScopes()
            ->where('table_visit_id', $visit->id)
            ->select('id');
        BillRequest::withoutGlobalScopes()
            ->whereIn('menu_session_id', $sessionIds)
            ->whereIn('status', [
                BillRequestStatus::REQUESTED->value,
                BillRequestStatus::SEEN->value,
                BillRequestStatus::IN_PROGRESS->value,
            ])->update([
                'status' => BillRequestStatus::COMPLETED->value,
                'completed_at' => now(),
                'updated_at' => now(),
            ]);

        MenuSession::withoutGlobalScopes()
            ->where('table_visit_id', $visit->id)
            ->whereNull('closed_at')
            ->update(['closed_at' => now(), 'updated_at' => now()]);

        $visit->forceFill([
            'status' => TableVisitStatus::CLOSED->value,
            'closed_at' => now(),
        ])->save();
    }

    /** Attach a pre-feature session lazily so deploys do not strand live diners. */
    public function attachSession(MenuSession $session): ?TableVisit
    {
        if ($session->table_visit_id !== null) {
            return $session->tableVisit;
        }
        if ($session->table === null || ! $session->isUsable()) {
            return null;
        }

        return DB::transaction(function () use ($session) {
            $visit = $this->activeForTable($session->table);
            $session->forceFill(['table_visit_id' => $visit->id])->save();
            $session->setRelation('tableVisit', $visit);

            return $visit;
        });
    }

    public function finish(DiningTable $table, User $user, TableVisitStatus $status): ?TableVisit
    {
        return DB::transaction(function () use ($table, $user, $status) {
            DiningTable::whereKey($table->id)->lockForUpdate()->firstOrFail();

            $visit = TableVisit::query()
                ->where('table_id', $table->id)
                ->where('status', TableVisitStatus::OPEN->value)
                ->lockForUpdate()
                ->latest('id')
                ->first();

            if ($visit === null) {
                return null;
            }

            $orderStatus = $status === TableVisitStatus::CLOSED
                ? OrderStatus::COMPLETED
                : OrderStatus::CANCELLED;
            // A cancelled visit cancels its running bill; record who and when,
            // as a direct cancellation would (no reason — the visit has none).
            $cancelStamp = $orderStatus === OrderStatus::CANCELLED
                ? ['cancelled_at' => now(), 'cancelled_by' => $user->id]
                : [];
            Order::where('table_visit_id', $visit->id)
                ->where('status', OrderStatus::NEW->value)
                ->update(['status' => $orderStatus->value, 'updated_at' => now()] + $cancelStamp);

            $billStatus = $status === TableVisitStatus::CLOSED
                ? BillRequestStatus::COMPLETED
                : BillRequestStatus::CANCELLED;
            $billValues = $status === TableVisitStatus::CLOSED
                ? ['completed_at' => now(), 'completed_by' => $user->id]
                : ['cancelled_at' => now()];
            BillRequest::whereIn('menu_session_id', MenuSession::where('table_visit_id', $visit->id)->select('id'))
                ->whereIn('status', [
                    BillRequestStatus::REQUESTED->value,
                    BillRequestStatus::SEEN->value,
                    BillRequestStatus::IN_PROGRESS->value,
                ])->update($billValues + ['status' => $billStatus->value, 'updated_at' => now()]);

            MenuSession::where('table_visit_id', $visit->id)
                ->whereNull('closed_at')
                ->update(['closed_at' => now(), 'updated_at' => now()]);

            $visit->forceFill([
                'status' => $status->value,
                'closed_at' => now(),
                'closed_by' => $user->id,
            ])->save();

            return $visit;
        });
    }
}
