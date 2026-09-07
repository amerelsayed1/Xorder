<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-009 close. variance_reason's conditional requirement depends on the
 * server-computed expected cash, so it is enforced in PosShiftService where
 * that figure exists — not here.
 */
class CloseShiftRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'acting_user_id' => ['nullable', 'integer'],
            'closed_at' => ['required', 'date'],
            'counted_cash_minor' => ['required', 'integer', 'min:0'],
            'denominations' => ['nullable', 'array', 'max:50'],
            'denominations.*.value_minor' => ['required_with:denominations', 'integer', 'min:1'],
            'denominations.*.count' => ['required_with:denominations', 'integer', 'min:0'],
            'variance_reason' => ['nullable', 'string', 'max:255'],
        ];
    }
}
