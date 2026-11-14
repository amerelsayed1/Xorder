<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-024: exactly 4 ASCII digits, write-only. The PIN itself never appears
 * in any response, any log, or any audit row.
 *
 * Exactly four, not the contract's original 4–6: the till's keypad submits on
 * the fourth digit — one tap fewer at every unlock, and deliberate — so a 5- or
 * 6-digit PIN set here could never be typed there and the cashier was locked
 * out for good (S2-2, 16 Oct 2026). The length is now the same on both sides;
 * the dashboard form, the contract text and the keypad all say four.
 */
class SetPosPinRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // per-target authorization is in the controller guard
    }

    public function rules(): array
    {
        return [
            'pin' => ['required', 'string', 'regex:/^[0-9]{4}$/'],
        ];
    }
}
