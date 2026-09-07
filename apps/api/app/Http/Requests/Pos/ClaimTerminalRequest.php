<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-023 Path A. Unauthenticated — the pairing code is the credential. */
class ClaimTerminalRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'tenant_slug' => ['required', 'string', 'max:100'],
            'pairing_code' => ['required', 'string', 'max:20'],
            'platform' => ['nullable', 'string', 'max:20'],
            'app_version' => ['nullable', 'string', 'max:32'],
            'fingerprint' => ['nullable', 'string', 'max:255'],
        ];
    }
}
