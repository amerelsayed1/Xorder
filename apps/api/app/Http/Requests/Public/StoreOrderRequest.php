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
            'customer_email' => ['nullable', 'email', 'max:150'],
            'customer_address' => ['nullable', 'string', 'max:500'],
            'address_label' => ['nullable', 'string', 'max:60'],
            'order_type' => ['nullable', 'string', 'in:pickup,delivery,dine_in'],
            'note' => ['nullable', 'string', 'max:1000'],
        ];
    }
}
