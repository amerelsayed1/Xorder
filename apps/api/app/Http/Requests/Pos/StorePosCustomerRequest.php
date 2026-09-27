<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-014 — a customer created at the counter.
 *
 * The phone is the identity, exactly as it is on the diner path: the directory
 * keys on `restaurant_id + phone` and `CustomerDirectory::upsert()` normalises
 * Arabic-Indic digits before it looks. So the field is required here even
 * though `name` reads like the more important one — a customer with no phone
 * cannot be found again, by this till or by the dashboard.
 */
class StorePosCustomerRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            // POS-BE-007: the till's own key, so a reply it never saw can be
            // replayed without creating a second customer.
            'client_transaction_id' => ['required', 'uuid'],
            'name' => ['required', 'string', 'max:150'],
            'phone' => ['required', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:255'],
            'address' => ['nullable', 'string', 'max:500'],
            'address_label' => ['nullable', 'string', 'max:60'],
            'acting_user_id' => ['nullable', 'integer'],
        ];
    }
}
