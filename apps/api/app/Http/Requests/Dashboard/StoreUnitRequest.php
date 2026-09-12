<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09: a unit. The shape rules are the till's CHECKs (xorder-pos migration
 * 39), enforced here because Blueprint has no portable CHECK.
 */
class StoreUnitRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        $merge = [];

        if (is_string($this->input('code'))) {
            $merge['code'] = strtolower(trim($this->input('code')));
        }

        // Absent or blank means the till's default, EA ("each").
        $eta = $this->input('eta_unit_type');
        if ($this->has('eta_unit_type') || $this->isMethod('post')) {
            $merge['eta_unit_type'] = is_string($eta) && trim($eta) !== '' ? strtoupper(trim($eta)) : 'EA';
        }

        $this->merge($merge);
    }

    public function rules(): array
    {
        return [
            'code' => [
                'required', 'string', 'regex:/^[a-z][a-z0-9_]{0,15}$/',
                Rule::unique('units', 'code')->where('restaurant_id', $this->user()->restaurant_id),
            ],
            ...$this->sharedRules(),
        ];
    }

    /** Everything but the code, which UpdateUnitRequest never accepts. */
    protected function sharedRules(): array
    {
        return [
            'name_en' => ['nullable', 'string', 'max:120'],
            'name_ar' => ['nullable', 'string', 'max:120'],
            'eta_unit_type' => ['sometimes', 'string', 'regex:/^[A-Z0-9]{1,6}$/'],
            'allows_fraction' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:1000000'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_en')) && blank($this->input('name_ar'))) {
                $validator->errors()->add('name_en', __('xorder.validation.unit_name_required'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'code.regex' => __('xorder.validation.unit_code_shape'),
            'code.unique' => __('xorder.validation.unit_code_taken'),
            'eta_unit_type.regex' => __('xorder.validation.unit_eta_shape'),
        ];
    }
}
