<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-024: 4–6 ASCII digits, write-only. The PIN itself never appears in
 * any response, any log, or any audit row.
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
            'pin' => ['required', 'string', 'regex:/^[0-9]{4,6}$/'],
        ];
    }
}
