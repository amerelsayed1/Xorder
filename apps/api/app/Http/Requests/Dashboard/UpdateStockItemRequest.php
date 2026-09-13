<?php

namespace App\Http\Requests\Dashboard;

/**
 * Same rules as store, with the current item's own unit and menu link
 * allowed. Whether the unit may CHANGE is decided by StockItemService under
 * a lock, not here: it depends on stock held and open orders.
 */
class UpdateStockItemRequest extends StoreStockItemRequest {}
