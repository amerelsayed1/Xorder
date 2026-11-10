<?php

namespace App\Http\Requests\Dashboard;

use App\Support\ContentLanguages;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09: a supplier, validated the till's way (xorder-pos supplier.dart
 * `problems`): a name and a phone number, and nothing else compulsory. Kept
 * short on purpose: a delivery recorded at seven in the morning needs who it
 * came from and how to reach them, not a form.
 *
 * The phone shape is deliberately loose (any 40 characters): a supplier is as
 * likely to be reached on a landline, an extension or a second number written
 * beside the first as on a mobile, and a delivery driver's scrap of paper is
 * not a place to argue about E.164.
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
        // '' and NULL mean the same thing: no code. NULL is what lets the
        // plain unique(restaurant_id, code) allow any number of suppliers
        // without one.
        if ($this->has('code')) {
            $code = is_string($this->input('code')) ? trim($this->input('code')) : $this->input('code');
            $this->merge(['code' => $code === '' ? null : $code]);
        }
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
            'phone' => ['required', 'string', 'max:40'],
            'email' => ['nullable', 'email', 'max:255'],
            'address' => ['nullable', 'string', 'max:1000'],
            'payment_term_days' => ['sometimes', 'integer', 'min:0', 'max:3650'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'is_active' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator) {
            ContentLanguages::checkName($this, $validator, 'xorder.validation.supplier_name_required');
        });
    }

    public function messages(): array
    {
        return [
            'code.unique' => __('xorder.validation.supplier_code_taken'),
            'phone.required' => __('xorder.validation.supplier_phone_required'),
        ];
    }
}
