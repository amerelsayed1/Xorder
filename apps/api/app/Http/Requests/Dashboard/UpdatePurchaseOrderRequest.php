<?php

namespace App\Http\Requests\Dashboard;

/**
 * Same shape as a new draft: PUT replaces the header and the lines wholesale.
 * Whether the order may still be edited (only a draft) is decided by
 * PurchaseOrderService under a lock on the order row, not here.
 */
class UpdatePurchaseOrderRequest extends StorePurchaseOrderRequest {}
