<?php

namespace App\Http\Requests\Dashboard;

/** Same shape as store: a supplier is always written whole. The code-unique rule ignores this row. */
class UpdateSupplierRequest extends StoreSupplierRequest {}
