<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-033 — rejecting an online order; the reason is shown to the diner. */
class RejectOnlineOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_request_id' => ['required', 'uuid'],
            'reason' => ['required', 'string', 'max:255'],
        ];
    }
}
