<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Generic reorder payload: { "order": [{ "id": 1, "display_order": 0 }, ...] }.
 * Ownership of each id is enforced in the controller via the tenant scope.
 */
class ReorderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        return [
            'order' => ['required', 'array', 'min:1'],
            'order.*.id' => ['required', 'integer'],
            'order.*.display_order' => ['required', 'integer', 'min:0'],
        ];
    }
}
