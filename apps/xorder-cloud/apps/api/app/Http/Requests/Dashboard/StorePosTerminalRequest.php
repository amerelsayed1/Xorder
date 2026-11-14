<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/** POS-BE-023: provision a terminal from the dashboard (state `provisioned`). */
class StorePosTerminalRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // route stack: role + feature:pos + can:pos.provision
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
