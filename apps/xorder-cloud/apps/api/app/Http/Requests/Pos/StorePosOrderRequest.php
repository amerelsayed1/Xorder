<?php

namespace App\Http\Requests\Pos;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POS-BE-006. Money fields are integer minor units — a float here is a client
 * bug and fails validation (D1: JSON never carries a float).
 *
 * v1 relaxations (2026-09-02): acting_user_id and shift_client_id nullable;
 * a line's variant may arrive inside option_ids[]; unit_price_minor is the
 * client-asserted figure used ONLY for the deleted-item fallback.
 */
class StorePosOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'client_transaction_id' => ['required', 'uuid'],
            'branch_id' => ['required', 'integer'],
            'order_type' => ['required', 'string', 'max:20'],
            'table_id' => ['nullable', 'integer'],
            'customer_id' => ['nullable', 'integer'],
            'acting_user_id' => ['nullable', 'integer'],
            'shift_client_id' => ['nullable', 'uuid'],
            'created_at' => ['required', 'date'],
            'priced_offline' => ['nullable', 'boolean'],
            'catalog_synced_at' => ['nullable', 'date'],
            'note' => ['nullable', 'string', 'max:1000'],
            // Guest paging, shared QR (POS-BE-035): the code a client reads out.
            // Not part of the idempotency hash and never a reason to refuse the
            // order; PagerSessionService::bind() reports what became of it.
            'pager_code' => ['nullable', 'string', 'max:16'],

            'lines' => ['required', 'array', 'min:1', 'max:200'],
            // POS-BE-010: the till's own key for the line ('L1', a local row
            // id — whatever it is, it must be unique within the order, which
            // the unique(order_id, client_line_id) index also enforces). It is
            // how a refund built offline names a line, and it is deliberately
            // NOT part of the idempotency hash: it carries no money, so a till
            // that starts sending it must not get a payload mismatch on an
            // order it already delivered without one.
            'lines.*.client_line_id' => ['nullable', 'string', 'max:64', 'distinct'],
            'lines.*.menu_item_id' => ['nullable', 'integer'],
            'lines.*.variant_option_id' => ['nullable', 'integer'],
            'lines.*.option_ids' => ['nullable', 'array', 'max:50'],
            'lines.*.option_ids.*' => ['integer'],
            'lines.*.quantity' => ['required', 'integer', 'min:1', 'max:999'],
            'lines.*.note' => ['nullable', 'string', 'max:500'],
            'lines.*.name_snapshot' => ['nullable', 'string', 'max:255', 'required_without:lines.*.menu_item_id'],
            'lines.*.unit_price_minor' => ['nullable', 'integer', 'min:0'],
            'lines.*.discount' => ['nullable', 'array'],
            'lines.*.discount.amount_minor' => ['required_with:lines.*.discount', 'integer', 'min:0'],
            'lines.*.discount.reason' => ['nullable', 'string', 'max:255'],
            'lines.*.price_override' => ['nullable', 'array'],
            'lines.*.price_override.unit_price_minor' => ['required_with:lines.*.price_override', 'integer', 'min:0'],
            'lines.*.price_override.reason' => ['nullable', 'string', 'max:255'],

            'order_discount' => ['nullable', 'array'],
            'order_discount.amount_minor' => ['nullable', 'integer', 'min:0'],
            'order_discount.reason' => ['nullable', 'string', 'max:255'],

            'asserted_totals' => ['nullable', 'array'],
            'asserted_totals.subtotal_minor' => ['required_with:asserted_totals', 'integer', 'min:0'],
            'asserted_totals.discount_minor' => ['required_with:asserted_totals', 'integer', 'min:0'],
            'asserted_totals.tax_minor' => ['required_with:asserted_totals', 'integer', 'min:0'],
            'asserted_totals.charges_minor' => ['required_with:asserted_totals', 'integer', 'min:0'],
            'asserted_totals.total_minor' => ['required_with:asserted_totals', 'integer', 'min:0'],

            'payments' => ['nullable', 'array', 'max:20'],
            'payments.*.client_transaction_id' => ['required', 'uuid', 'distinct'],
            'payments.*.tender_type_id' => ['nullable', 'integer'],
            'payments.*.amount_minor' => ['required', 'integer', 'min:1'],
            'payments.*.received_at' => ['nullable', 'date'],
        ];
    }
}
