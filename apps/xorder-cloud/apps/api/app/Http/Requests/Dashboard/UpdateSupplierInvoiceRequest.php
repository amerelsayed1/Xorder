<?php

namespace App\Http\Requests\Dashboard;

/**
 * CB-09 slice c: an invoice is rewritten whole, so its update rules are its
 * create rules. Whether it may change at all (live, nothing allocated) is the
 * ledger service's decision, under a lock on the invoice.
 */
class UpdateSupplierInvoiceRequest extends StoreSupplierInvoiceRequest {}
