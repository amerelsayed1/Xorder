<?php

namespace App\Services;

use App\Enums\PurchaseStatus;
use App\Exceptions\PurchasingRefusal;
use App\Models\PurchaseOrderLine;
use App\Models\StockItem;
use App\Models\StockLevel;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice b: stock items. Creation is plain; changing the UNIT is the
 * one rule that needs a lock.
 *
 * A unit change is refused while the item:
 *   - holds a non-zero quantity in any branch (10 box + 5 kg must never be
 *     stored as 15 kg: the till's §10 C3 gap), or
 *   - sits on a draft, sent or part-received order, whose lines were
 *     written in the old unit and would book it in against the new one.
 *
 * The item row is locked FOR UPDATE; receiving and draft saves take it FOR
 * SHARE, so a unit change and a receipt of the same item serialise.
 */
class StockItemService
{
    /** @param array<string,mixed> $data validated */
    public function create(array $data, User $by): StockItem
    {
        $item = new StockItem($data);
        $item->forceFill(['updated_by' => $by->id])->save();

        return $item;
    }

    /** @param array<string,mixed> $data validated */
    public function update(StockItem $item, array $data, User $by): StockItem
    {
        return DB::transaction(function () use ($item, $data, $by) {
            $locked = StockItem::query()->whereKey($item->id)->lockForUpdate()->firstOrFail();

            if (isset($data['unit_code']) && $data['unit_code'] !== $locked->unit_code) {
                if (self::holdsStock($locked->id)) {
                    throw PurchasingRefusal::conflict('STOCK_ITEM_UNIT_LOCKED', 'unit_locked_held');
                }
                if (self::onOpenOrder($locked->id)) {
                    throw PurchasingRefusal::conflict('STOCK_ITEM_ON_OPEN_ORDER', 'unit_locked_on_order');
                }
            }

            $locked->fill($data)->forceFill(['updated_by' => $by->id])->save();

            return $locked;
        });
    }

    public static function holdsStock(int $itemId): bool
    {
        return StockLevel::withoutGlobalScopes()
            ->where('stock_item_id', $itemId)
            ->where('quantity_milli', '!=', 0)
            ->exists();
    }

    public static function onOpenOrder(int $itemId): bool
    {
        return PurchaseOrderLine::withoutGlobalScopes()
            ->where('stock_item_id', $itemId)
            ->whereHas('purchaseOrder', fn ($q) => $q->withoutGlobalScopes()->whereIn('status', [
                PurchaseStatus::DRAFT->value, PurchaseStatus::SENT->value, PurchaseStatus::PARTIALLY_RECEIVED->value,
            ]))
            ->exists();
    }
}
