<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-009 cash in / out. Requires an OPEN shift (SHIFT_NOT_OPEN otherwise). */
class StoreCashMovementRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'shift_client_id' => ['required', 'uuid'],
            'direction' => ['required', 'in:in,out'],
            'amount_minor' => ['required', 'integer', 'min:1'],
            'reason' => ['required', 'string', 'max:120'],
            'reference' => ['nullable', 'string', 'max:255'],
            'acting_user_id' => ['nullable', 'integer'],
            'occurred_at' => ['required', 'date'],
        ];
    }
}
