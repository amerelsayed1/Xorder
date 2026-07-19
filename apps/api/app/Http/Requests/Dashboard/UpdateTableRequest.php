<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateTableRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isRestaurantAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurantId = $this->user()->restaurant_id;
        $table = $this->route('table');
        $areaId = $this->input('dining_area_id', $table?->dining_area_id);

        return [
            'dining_area_id' => [
                'sometimes',
                Rule::exists('dining_areas', 'id')
                    ->where('restaurant_id', $restaurantId)
                    ->where('is_active', true),
            ],
            'label' => [
                'sometimes', 'required', 'string', 'max:60',
                Rule::unique('dining_tables', 'label')
                    ->where('dining_area_id', $areaId)
                    ->ignore($table?->id),
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
