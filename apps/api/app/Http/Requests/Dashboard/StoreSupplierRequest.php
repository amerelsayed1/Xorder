<?php

namespace App\Http\Requests\Dashboard;

use App\Rules\MobileNumber;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09: a supplier, validated the till's way (xorder-pos supplier.dart
 * `problems`): a name, non-negative payment terms, and a tax registration
 * number that is exactly nine digits when given. Kept short on purpose: a
 * delivery recorded at seven in the morning needs who it came from, not a form.
 *
 * Written whole, like the POS money config: update reuses these rules.
 */
class StoreSupplierRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        $merge = [];

        // '' and NULL mean the same thing: no code. NULL is what lets the
        // plain unique(restaurant_id, code) allow any number of suppliers
        // without one.
        if ($this->has('code')) {
            $code = is_string($this->input('code')) ? trim($this->input('code')) : $this->input('code');
            $merge['code'] = $code === '' ? null : $code;
        }

        // Typed on an Arabic keyboard, ٢٠٤١٢٣٤٥٦ is the same number.
        if ($this->has('tax_number')) {
            $tax = $this->input('tax_number');
            $tax = is_string($tax) ? MobileNumber::normalizeDigits($tax) : $tax;
            $merge['tax_number'] = $tax === '' ? null : $tax;
        }

        $this->merge($merge);
    }

    public function rules(): array
    {
        return [
            'name_en' => ['nullable', 'string', 'max:160'],
            'name_ar' => ['nullable', 'string', 'max:160'],
            'code' => [
                'nullable', 'string', 'max:40',
                Rule::unique('suppliers', 'code')
                    ->where('restaurant_id', $this->user()->restaurant_id)
                    ->ignore($this->route('supplier')),
            ],
            'contact_name' => ['nullable', 'string', 'max:160'],
            'phone' => ['nullable', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:255'],
            'address' => ['nullable', 'string', 'max:1000'],
            'tax_number' => ['nullable', 'string', 'regex:/^[0-9]{9}$/'],
            'payment_term_days' => ['sometimes', 'integer', 'min:0', 'max:3650'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            if (blank($this->input('name_en')) && blank($this->input('name_ar'))) {
                $validator->errors()->add('name_en', __('xorder.validation.supplier_name_required'));
            }
        });
    }

    public function messages(): array
    {
        return [
            'code.unique' => __('xorder.validation.supplier_code_taken'),
            'tax_number.regex' => __('xorder.validation.supplier_tax_number'),
        ];
    }
}
