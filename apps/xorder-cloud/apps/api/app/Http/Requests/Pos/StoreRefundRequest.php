<?php

namespace App\Http\Requests\Pos;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-010. Money is integer minor units — a float here is a client bug.
 *
 * `order_id` is a string on purpose: it accepts the server id OR the order's
 * own `client_transaction_id` (UUID detected by format), because an offline
 * till refunding an order that is still in its outbox knows only its own key.
 *
 * A line names itself with `order_item_id` (the server's id, when the till has
 * the order response in hand) or `client_line_id` (the key the till stamped on
 * the order line). **Exactly one**, and never both — a line that answers to two
 * names is a line whose identity nobody can settle later.
 */
class StoreRefundRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            // Server id or the order's client_transaction_id.
            'order_id' => ['required', 'string', 'max:64'],
            'kind' => ['nullable', 'in:refund,void'],
            'reason' => ['nullable', 'string', 'max:255'],
            'acting_user_id' => ['nullable', 'integer'],
            'authorized_by_user_id' => ['nullable', 'integer'],
            'shift_client_id' => ['nullable', 'uuid'],
            'occurred_at' => ['required', 'date'],

            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.order_item_id' => ['nullable', 'integer', 'distinct'],
            'lines.*.client_line_id' => ['nullable', 'string', 'max:64', 'distinct'],
            'lines.*.quantity' => ['required', 'integer', 'min:1', 'max:999'],
            'lines.*.amount_minor' => ['required', 'integer', 'min:0'],

            'tenders' => ['required', 'array', 'min:1', 'max:20'],
            'tenders.*.tender_type_id' => ['nullable', 'integer'],
            'tenders.*.amount_minor' => ['required', 'integer', 'min:1'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator) {
            foreach ((array) $this->input('lines', []) as $index => $line) {
                $hasServerId = filled($line['order_item_id'] ?? null);
                $hasClientKey = filled($line['client_line_id'] ?? null);

                if ($hasServerId === $hasClientKey) {
                    $validator->errors()->add(
                        "lines.$index.client_line_id",
                        'Name the line with exactly one of order_item_id or client_line_id.',
                    );
                }
            }
        });
    }
}
