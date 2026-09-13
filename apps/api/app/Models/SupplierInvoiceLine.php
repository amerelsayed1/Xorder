<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use App\Support\StockCosting;
use Illuminate\Database\Eloquent\Model;

/**
 * CB-09 slice c: one line of a supplier's invoice, as the paper says it.
 * Optional (the till's invoices have none). No stock item: an invoice line
 * never moves or reprices stock. `restaurant_id` is stamped from the invoice.
 */
class SupplierInvoiceLine extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'supplier_invoice_id' => 'integer',
            'quantity_milli' => 'integer',
            'unit_cost_minor' => 'integer',
            'tax_rate_bp' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    /** The line's value before tax: the one rounding point (costAt). */
    public function lineTotalMinor(): int
    {
        return StockCosting::costAt($this->quantity_milli, $this->unit_cost_minor);
    }
}
