<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * CB-09 slice b: a delivery booked in against a purchase order.
 *
 *   {lines: [{line_id, quantity_milli}], occurred_at?, note?}
 *
 * Quantities are integer thousandths. A zero is allowed and ignored (the
 * receive form prefills every line and a person clears the ones that didn't
 * come). Over-delivery is allowed: suppliers round up to a crate. Whether a
 * line belongs to this order, whether the order is open, and the unit rules
 * are ReceivingService's, under its locks.
 */
class ReceivePurchaseOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'lines' => ['required', 'array', 'min:1', 'max:'.StorePurchaseOrderRequest::MAX_LINES],
            'lines.*' => ['array'],
            'lines.*.line_id' => ['required', 'integer', 'distinct'],
            'lines.*.quantity_milli' => ['required', 'integer', 'min:0', 'max:'.StorePurchaseOrderRequest::MAX_QUANTITY_MILLI],
            // A delivery can be booked in late, but not ahead of time (a few
            // minutes of clock drift between the browser and us is tolerated).
            'occurred_at' => ['nullable', 'date', 'before_or_equal:'.now()->addMinutes(10)->toIso8601String()],
            'note' => ['nullable', 'string', 'max:1000'],
        ];
    }

    /** @return array<int,int> line id => quantity_milli */
    public function quantities(): array
    {
        $out = [];
        foreach ($this->validated('lines') as $line) {
            $out[(int) $line['line_id']] = (int) $line['quantity_milli'];
        }

        return $out;
    }
}
