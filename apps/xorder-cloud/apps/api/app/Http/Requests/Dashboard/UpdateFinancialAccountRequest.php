<?php

namespace App\Http\Requests\Dashboard;

/** XORD-015: same rules as creating; the unique-name rule ignores the account being edited. */
class UpdateFinancialAccountRequest extends StoreFinancialAccountRequest {}
