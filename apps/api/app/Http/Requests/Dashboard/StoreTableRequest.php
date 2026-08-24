<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreTableRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('tables.create') ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;

        return [
            // Must be an active area of this restaurant — disabled areas are not
            // selectable for new tables (FR-AREA-008).
            'dining_area_id' => [
                'required',
                Rule::exists('dining_areas', 'id')
                    ->where('restaurant_id', $restaurantId)
                    ->where('is_active', true),
            ],
            // Name/number is unique within its dining area (FR-TABLE-003).
            'label' => [
                'required', 'string', 'max:60',
                Rule::unique('dining_tables', 'label')->where('dining_area_id', $this->input('dining_area_id')),
            ],
            'seats_count' => ['nullable', 'integer', 'min:1', 'max:100'],
            'notes' => ['nullable', 'string', 'max:500'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return ['label.unique' => __('xorder.validation.table_label_taken')];
    }
}
