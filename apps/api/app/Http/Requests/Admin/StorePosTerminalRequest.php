<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Super Admin creates a terminal for an existing tenant.
 *
 * The tenant is a ROUTE parameter, not input — this mirrors
 * admin/restaurants/{restaurant}/admin and .../subscription rather than
 * StoreLicenceRequest's body-borne restaurant_id, because the operator is
 * already standing on one tenant's page when they do this.
 *
 * Deliberately the same four fields as the dashboard's own request: a
 * terminal created from the platform side must be indistinguishable from one
 * the restaurant provisioned itself.
 */
class StorePosTerminalRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('pos_fleet.manage') ?? false;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:60'],
            'branch_id' => ['required', 'integer'],
            'deployment_mode' => ['nullable', 'string', 'in:cloud'],
            'sync_policy' => ['nullable', 'string', 'in:dynamic,manual'],
        ];
    }
}
