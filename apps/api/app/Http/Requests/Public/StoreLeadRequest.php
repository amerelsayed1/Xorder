<?php

namespace App\Http\Requests\Public;

use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;

class StoreLeadRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'restaurant_name' => ['required', 'string', 'max:150'],
            'contact_name' => ['nullable', 'string', 'max:150'],
            'whatsapp' => ['required', 'string', 'max:40', new MobileNumber],
            'city' => ['nullable', 'string', 'max:100'],
            'business_type' => ['nullable', 'string', 'max:80'],
            'message' => ['nullable', 'string', 'max:2000'],
            'source' => ['nullable', 'string', 'max:120'],
        ];
    }
}
