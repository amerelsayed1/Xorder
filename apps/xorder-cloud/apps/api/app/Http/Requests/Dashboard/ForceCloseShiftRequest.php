<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * dashboard-shift-details: closing a revoked till's shift from the dashboard.
 * Both fields are required (owner decision 2026-11-09): someone counted the
 * drawer, and the record says why the till did not close it.
 */
class ForceCloseShiftRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'counted_cash_minor' => ['required', 'integer', 'min:0', 'max:2000000000'],
            'reason' => ['required', 'string', 'min:3', 'max:500'],
        ];
    }
}
