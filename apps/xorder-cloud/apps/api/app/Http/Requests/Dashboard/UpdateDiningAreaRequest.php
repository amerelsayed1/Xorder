<?php

namespace App\Http\Requests\Dashboard;

use App\Http\Requests\Concerns\PreservesDisabledLanguages;
use App\Support\ContentLanguages;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateDiningAreaRequest extends FormRequest
{
    use PreservesDisabledLanguages;

    public function authorize(): bool
    {
        return $this->user()?->can('tables.update') ?? false;
    }

    public function rules(): array
    {
        return [
            'branch_id' => [
                'sometimes',
                Rule::exists('branches', 'id')->where('restaurant_id', $this->user()->restaurant_id),
            ],
            'name_ar' => ['nullable', 'string', 'max:150'],
            'name_en' => ['nullable', 'string', 'max:150'],
            'type' => ['nullable', 'string', 'max:40'],
            'description' => ['nullable', 'string', 'max:1000'],
            'display_order' => ['nullable', 'integer', 'min:0'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.area_name_required', partial: true);
        });
    }
}
