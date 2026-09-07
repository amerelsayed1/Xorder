<?php

namespace App\Http\Resources;

use App\Models\PosShift;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin PosShift */
class PosShiftResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'client_transaction_id' => $this->client_transaction_id,
            'branch_id' => $this->branch_id,
            'status' => $this->status,
            'opened_at' => $this->opened_at?->toIso8601String(),
            'closed_at' => $this->closed_at?->toIso8601String(),
            'opened_by_id' => $this->opened_by_id,
            'closed_by_id' => $this->closed_by_id,
            'opening_float_minor' => (int) $this->opening_float_minor,
            'counted_cash_minor' => $this->counted_cash_minor !== null ? (int) $this->counted_cash_minor : null,
            'expected_cash_minor' => $this->expected_cash_minor !== null ? (int) $this->expected_cash_minor : null,
            'variance_minor' => $this->variance_minor !== null ? (int) $this->variance_minor : null,
            'variance_reason' => $this->variance_reason,
            'denominations' => $this->denominations,
        ];
    }
}
