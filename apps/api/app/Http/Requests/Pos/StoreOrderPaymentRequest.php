<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** §006-P — settle an open bill later, one payment per request, its own key. */
class StoreOrderPaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'tender_type_id' => ['nullable', 'integer'],
            'amount_minor' => ['required', 'integer', 'min:1'],
            'acting_user_id' => ['nullable', 'integer'],
            'shift_client_id' => ['nullable', 'uuid'],
            'received_at' => ['nullable', 'date'],
        ];
    }
}
