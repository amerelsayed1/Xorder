<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-009. opened_at is the CLIENT's time and is stored as sent. */
class OpenShiftRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'branch_id' => ['required', 'integer'],
            'acting_user_id' => ['nullable', 'integer'],
            'opened_at' => ['required', 'date'],
            'opening_float_minor' => ['required', 'integer', 'min:0'],
        ];
    }
}
