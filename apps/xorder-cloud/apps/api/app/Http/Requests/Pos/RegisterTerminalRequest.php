<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-023 Path B. Route stack gates auth + feature + pos.provision. */
class RegisterTerminalRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'name' => ['required', 'string', 'max:60'],
            'branch_id' => ['required', 'integer'],
            'deployment_mode' => ['nullable', 'string', 'in:cloud'],
            'sync_policy' => ['nullable', 'string', 'in:dynamic,manual'],
            'platform' => ['nullable', 'string', 'max:20'],
            'app_version' => ['nullable', 'string', 'max:32'],
            'fingerprint' => ['nullable', 'string', 'max:255'],
        ];
    }
}
