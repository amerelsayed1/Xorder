<?php

namespace App\Http\Requests\Public;

use App\Rules\MobileNumber;
use App\Services\DinerOrderPricing;
use Illuminate\Foundation\Http\FormRequest;

class StoreOrderRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Never reject an order over the soft order_type field: older/cached menu
     * clients send a localized label ("توصيل") rather than the enum value.
     * Normalize known labels to the enum; drop anything unknown to null.
     */
    protected function prepareForValidation(): void
    {
        if (! $this->has('order_type')) {
            return;
        }

        $raw = trim((string) $this->input('order_type'));
        $map = [
            'pickup' => 'pickup', 'delivery' => 'delivery',
            'dine_in' => 'dine_in', 'dine-in' => 'dine_in', 'dine in' => 'dine_in',
            'استلام' => 'pickup', 'توصيل' => 'delivery', 'في المطعم' => 'dine_in', 'محلي' => 'dine_in',
        ];

        $this->merge(['order_type' => $map[mb_strtolower($raw)] ?? $map[$raw] ?? null]);
    }

    /**
     * **The server prices every line (XORD-047).** A line names what was
     * ordered — `kind` (item or combo), `menu_item_id` or `combo_id`, and the
     * `option_ids` chosen — and {@see DinerOrderPricing} reads
     * the price, the names and the labels from the menu. Whatever the phone
     * sends as `name`, `variant`, `options`, `line_total` or `total` is accepted
     * for well-formedness and then IGNORED: it was the hole a modified request
     * walked through to set its own price.
     *
     * A line with no id is what a menu tab loaded before this release sends.
     * It is refused with "please refresh" for every restaurant (owner decision
     * A5, 2026-11-06): there is no window in which a client-priced order is
     * still accepted.
     */
    public function rules(): array
    {
        return [
            'items' => ['required', 'array', 'min:1', 'max:100'],
            'items.*.kind' => ['required', 'string', 'in:item,combo'],
            'items.*.menu_item_id' => ['required_if:items.*.kind,item', 'nullable', 'integer'],
            'items.*.combo_id' => ['required_if:items.*.kind,combo', 'nullable', 'integer'],
            'items.*.option_ids' => ['sometimes', 'array', 'max:40'],
            'items.*.option_ids.*' => ['integer'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:99'],
            // Display text from older clients; ignored, the server names lines.
            'items.*.name' => ['nullable', 'string', 'max:200'],
            'items.*.variant' => ['nullable', 'string', 'max:200'],
            'items.*.options' => ['sometimes', 'array', 'max:20'],
            'items.*.options.*' => ['string', 'max:200'],
            // The diner's per-line note ("no garlic"). Without this rule the
            // menu's note was silently stripped by validated() and never
            // reached the kitchen.
            'items.*.note' => ['nullable', 'string', 'max:500'],
            'items.*.line_total' => ['nullable', 'numeric', 'min:0', 'max:1000000'],
            'total' => ['nullable', 'numeric', 'min:0', 'max:1000000'],
            // Which language the server names the lines in; the diner's.
            'lang' => ['nullable', 'string', 'in:ar,en'],
            'customer_name' => ['nullable', 'string', 'max:150'],
            'customer_phone' => ['nullable', 'string', 'max:32', new MobileNumber],
            'customer_email' => ['nullable', 'email', 'max:150'],
            'customer_address' => ['nullable', 'string', 'max:500'],
            'address_label' => ['nullable', 'string', 'max:60'],
            'order_type' => ['nullable', 'string', 'in:pickup,delivery,dine_in'],
            'note' => ['nullable', 'string', 'max:1000'],
            // Present when the order comes from a table QR session (Phase 1).
            'session_token' => ['nullable', 'string', 'size:40'],
        ];
    }

    /** An old menu tab (no ids) is told to refresh, not shown a field error. */
    public function messages(): array
    {
        $refresh = __('xorder.messages.menu_refresh_required');

        return [
            'items.*.kind.required' => $refresh,
            'items.*.menu_item_id.required_if' => $refresh,
            'items.*.combo_id.required_if' => $refresh,
        ];
    }
}
