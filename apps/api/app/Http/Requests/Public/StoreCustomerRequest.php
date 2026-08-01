<?php

namespace App\Http\Requests\Public;

use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;

/**
 * A guest's contact details captured at WhatsApp checkout so the restaurant
 * still builds a customer directory even when no system order is recorded.
 */
class StoreCustomerRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'customer_name' => ['nullable', 'string', 'max:150'],
            'customer_phone' => ['required', 'string', 'max:32', new MobileNumber],
            'customer_email' => ['nullable', 'email', 'max:150'],
            'customer_address' => ['nullable', 'string', 'max:500'],
            'address_label' => ['nullable', 'string', 'max:60'],
        ];
    }
}
