<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Create many tables in one action from an explicit list of names the owner
 * typed in the dialog (Enter adds a field, Save creates them all). The
 * controller trims/de-duplicates the list and checks the names for collisions
 * within the area before inserting, so the same per-area uniqueness rule as
 * single create still holds.
 */
class BulkStoreTablesRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            'dining_area_id' => [
                'required',
                Rule::exists('dining_areas', 'id')
                    ->where('restaurant_id', $restaurantId)
                    ->where('is_active', true),
            ],
            // One label per table. Cap the batch so a single request can't spawn
            // thousands of rows; blanks are dropped by the controller.
            'labels' => ['required', 'array', 'min:1', 'max:100'],
            'labels.*' => ['nullable', 'string', 'max:60'],
            'seats_count' => ['nullable', 'integer', 'min:1', 'max:100'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }
}
