<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\InvoiceVoidReason;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/** CB-09 slice c: a void carries one of the till's reason codes; `other` needs a note. */
class VoidSupplierInvoiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'reason' => ['required', Rule::enum(InvoiceVoidReason::class)],
            'note' => ['nullable', 'string', 'max:1000', 'required_if:reason,'.InvoiceVoidReason::OTHER->value],
        ];
    }

    public function messages(): array
    {
        return ['note.required_if' => __('xorder.validation.void_note_required')];
    }

    public function reason(): InvoiceVoidReason
    {
        return InvoiceVoidReason::from($this->validated('reason'));
    }
}
