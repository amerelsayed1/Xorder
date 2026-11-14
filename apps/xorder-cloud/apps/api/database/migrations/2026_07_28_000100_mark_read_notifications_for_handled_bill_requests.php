<?php

use App\Enums\BillRequestStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // One-time cleanup: before BillRequestController::updateStatus started
        // clearing the linked notification, acting on a request left its
        // 'bill_request.created' alert unread forever. Mark those historical alerts
        // read so the bell no longer shows an orange dot for requests that were
        // already seen, completed, or cancelled.
        //
        // The bill_request_id linkage lives on notifications.data (stored as a
        // string by PublicBillRequestController). Query-builder JSON access keeps
        // this portable across sqlite (tests) and postgres (production).
        $handledBillIds = DB::table('bill_requests')
            ->where('status', '!=', BillRequestStatus::REQUESTED->value)
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->all();

        if ($handledBillIds === []) {
            return;
        }

        DB::table('notifications')
            ->where('type', 'bill_request.created')
            ->whereNull('read_at')
            ->whereIn('data->bill_request_id', $handledBillIds)
            ->update(['read_at' => DB::raw('CURRENT_TIMESTAMP')]);
    }

    public function down(): void
    {
        // No-op: which of these notifications were originally unread cannot be
        // reconstructed, and re-flagging handled requests as unread is undesirable.
    }
};
