<?php

namespace App\Http\Requests\Public;

use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;

class SignupRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'restaurant_name' => ['required', 'string', 'max:150'],
            'restaurant_name_ar' => ['nullable', 'string', 'max:150'],
            'name' => ['required', 'string', 'max:150'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'whatsapp' => ['nullable', 'string', 'max:40', new MobileNumber],
        ];
    }
}
