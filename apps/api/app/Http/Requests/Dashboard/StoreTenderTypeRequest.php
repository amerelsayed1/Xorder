<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-013: tender kinds are data, not a processor integration. `wallet` is an
 * e-wallet (InstaPay and the like), added 2026-10-26 so a wallet method pairs
 * with wallet accounts on the platform as it does on an offline till.
 */
class StoreTenderTypeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'kind' => ['required', 'in:cash,card,wallet,external,other'],
            'is_active' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ];
    }
}
