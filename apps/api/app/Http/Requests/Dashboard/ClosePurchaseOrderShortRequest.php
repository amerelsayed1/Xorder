<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\PurchaseCloseReason;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * CB-09 D11: closing a part delivery short needs a reason code; `other`
 * needs a note. Whether the order can be closed at all is decided by
 * PurchaseOrderService under a lock on the order.
 */
class ClosePurchaseOrderShortRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'reason' => ['required', Rule::enum(PurchaseCloseReason::class)],
            'note' => ['nullable', 'string', 'max:1000', 'required_if:reason,'.PurchaseCloseReason::OTHER->value],
        ];
    }

    public function messages(): array
    {
        return ['note.required_if' => __('xorder.validation.void_note_required')];
    }

    public function reason(): PurchaseCloseReason
    {
        return PurchaseCloseReason::from($this->validated('reason'));
    }
}
