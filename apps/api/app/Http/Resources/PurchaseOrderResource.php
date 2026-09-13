<?php

namespace App\Http\Resources;

use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Services\PurchaseOrderService;
use App\Support\StockCosting;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * CB-09 slice b: a purchase order as the dashboard reads it.
 *
 * `totals` is the snapshot taken at send for anything past draft, and the
 * live figure (same arithmetic, PurchaseOrderService::totals) for a draft,
 * whose snapshot columns are still zero. Every figure is computed here, on
 * integers, so the browser never multiplies money.
 *
 * Lines are included when they were loaded.
 *
 * @mixin PurchaseOrder
 */
class PurchaseOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        /** @var PurchaseOrder $o */
        $o = $this->resource;
        $lines = $o->relationLoaded('lines') ? $o->lines : null;

        $totals = $o->status->isEditable() && $lines !== null
            ? PurchaseOrderService::totals($lines)
            : ['subtotal_minor' => $o->subtotal_minor, 'tax_minor' => $o->tax_minor, 'total_minor' => $o->total_minor];

        return [
            'id' => $o->id,
            'reference' => $o->reference,
            'status' => $o->status->value,
            'is_editable' => $o->status->isEditable(),
            'is_open' => $o->status->isOpen(),
            'can_cancel' => $o->status->canCancel(),
            'branch_id' => $o->branch_id,
            'branch' => $o->relationLoaded('branch') && $o->branch
                ? ['id' => $o->branch->id, 'name_en' => $o->branch->name_en, 'name_ar' => $o->branch->name_ar]
                : null,
            'supplier_id' => $o->supplier_id,
            'supplier_name' => $o->supplier_name,
            'supplier' => $o->relationLoaded('supplier') && $o->supplier
                ? ['id' => $o->supplier->id, 'name_en' => $o->supplier->name_en, 'name_ar' => $o->supplier->name_ar, 'is_active' => $o->supplier->is_active]
                : null,
            'currency' => $o->currency,
            'exponent' => $o->exponent,
            'totals' => $totals,
            'received_value_minor' => $lines !== null ? PurchaseOrderService::receivedValue($lines) : null,
            'ordered_at' => $o->ordered_at?->toIso8601String(),
            'expected_at' => $o->expected_at?->format('Y-m-d'),
            'notes' => $o->notes,
            'created_at' => $o->created_at?->toIso8601String(),
            'updated_at' => $o->updated_at?->toIso8601String(),
            'lines_count' => $lines?->count() ?? $o->lines_count,
            'lines' => $lines?->map(fn (PurchaseOrderLine $l) => [
                'id' => $l->id,
                'stock_item_id' => $l->stock_item_id,
                'stock_item' => $l->relationLoaded('stockItem') && $l->stockItem
                    ? ['id' => $l->stockItem->id, 'name_en' => $l->stockItem->name_en, 'name_ar' => $l->stockItem->name_ar, 'unit_code' => $l->stockItem->unit_code, 'is_active' => $l->stockItem->is_active]
                    : null,
                'description' => $l->description,
                'sku' => $l->sku,
                'unit_code' => $l->unit_code,
                'ordered_milli' => $l->ordered_milli,
                'received_milli' => $l->received_milli,
                'outstanding_milli' => $l->outstandingMilli(),
                'unit_cost_minor' => $l->unit_cost_minor,
                'tax_rate_bp' => $l->tax_rate_bp,
                'line_total_minor' => $l->lineTotalMinor(),
                'received_value_minor' => StockCosting::costAt($l->received_milli, $l->unit_cost_minor),
            ])->values()->all(),
        ];
    }
}
