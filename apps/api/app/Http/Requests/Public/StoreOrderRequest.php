<?php

namespace App\Http\Requests\Public;

use Illuminate\Foundation\Http\FormRequest;

class StoreOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Totals are informational — no payment is taken through this endpoint
     * (the order is fulfilled over WhatsApp), so the snapshot only needs to
     * be well-formed, not re-priced server-side.
     */
    public function rules(): array
    {
        return [
            'items' => ['required', 'array', 'min:1', 'max:100'],
            'items.*.name' => ['required', 'string', 'max:200'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:99'],
            'items.*.options' => ['sometimes', 'array', 'max:20'],
            'items.*.options.*' => ['string', 'max:200'],
            'items.*.line_total' => ['required', 'numeric', 'min:0', 'max:1000000'],
            'total' => ['required', 'numeric', 'min:0', 'max:1000000'],
            'customer_name' => ['nullable', 'string', 'max:150'],
            'customer_phone' => ['nullable', 'string', 'max:32'],
            'note' => ['nullable', 'string', 'max:1000'],
        ];
    }
}
