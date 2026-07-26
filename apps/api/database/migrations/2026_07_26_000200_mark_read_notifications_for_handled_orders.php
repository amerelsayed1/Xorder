<?php

use App\Enums\OrderStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // One-time cleanup: before OrderController::updateStatus started clearing
        // the linked notification, acting on an order left its 'order.created'
        // alert unread forever. Mark those historical alerts read so the bell no
        // longer shows an orange dot for orders that were already handled.
        //
        // The order_id linkage lives on notifications.data (stored as a string by
        // PublicOrderController). Query-builder JSON access keeps this portable
        // across sqlite (tests) and postgres (production).
        $handledOrderIds = DB::table('orders')
            ->where('status', '!=', OrderStatus::NEW->value)
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->all();

        if ($handledOrderIds === []) {
            return;
        }

        DB::table('notifications')
            ->where('type', 'order.created')
            ->whereNull('read_at')
            ->whereIn('data->order_id', $handledOrderIds)
            ->update(['read_at' => DB::raw('CURRENT_TIMESTAMP')]);
    }

    public function down(): void
    {
        // No-op: which of these notifications were originally unread cannot be
        // reconstructed, and re-flagging handled orders as unread is undesirable.
    }
};
