<?php

namespace App\Http\Requests\Dashboard;

/**
 * CB-09: a unit's code is immutable. It is simply not a rule here, so a `code`
 * in the body never reaches validated() and can't change the stored one.
 * Purchase lines and stock rows (slice b) store the code, so changing it would
 * silently change what they measured.
 */
class UpdateUnitRequest extends StoreUnitRequest
{
    public function rules(): array
    {
        return $this->sharedRules();
    }
}
