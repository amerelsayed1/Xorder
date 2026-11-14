<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-022. Everything optional beyond identity: a sick till must be able to
 * say "I'm alive" with whatever it knows, and an unrecognised field is
 * ignored, never an error — the heartbeat must not be breakable.
 */
class HeartbeatRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'app_version' => ['nullable', 'string', 'max:32'],
            'platform' => ['nullable', 'string', 'max:20'],
            'deployment_mode' => ['nullable', 'string', 'max:20'],
            'sync_policy' => ['nullable', 'string', 'max:20'],
            'pending_count' => ['nullable', 'integer', 'min:0'],
            'oldest_pending_at' => ['nullable', 'date'],
            'shift_open' => ['nullable', 'boolean'],
            'licence_expires_at' => ['nullable', 'date'],
            'clock_offset_seconds' => ['nullable', 'integer'],
            'last_catalog_sync_at' => ['nullable', 'date'],
        ];
    }
}
