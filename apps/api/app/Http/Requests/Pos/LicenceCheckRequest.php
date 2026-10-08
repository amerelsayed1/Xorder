<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/**
 * R2, POS-BE-031. Everything optional, like the heartbeat: the check answers
 * from the terminal's own tenant, and what the till reports is telemetry. A
 * till must never be refused its verdict over a field it sent badly.
 */
class LicenceCheckRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'fingerprint' => ['nullable', 'string', 'max:128'],
            'deployment_mode' => ['nullable', 'string', 'max:20'],
            'app_version' => ['nullable', 'string', 'max:32'],
            'licence_expires_at' => ['nullable', 'date'],
        ];
    }
}
