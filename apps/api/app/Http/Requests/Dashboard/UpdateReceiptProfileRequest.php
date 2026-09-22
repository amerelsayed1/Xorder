<?php

namespace App\Http\Requests\Dashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * A3 — the receipt profile for one branch.
 *
 * Validation is deliberately loose on SHAPE and strict on LENGTH: a restaurant
 * fills a profile like this in over a week, half a field at a time, and a
 * server that refused a nine-digit registration number typed as four digits
 * would make the form unusable. The till already decides, per field, what is
 * enough to PRINT (a trade name) versus enough to FILE with ETA (all of it) —
 * see `ReceiptProfile.printProblems` / `.filingProblems`. That judgement stays
 * where the receipt and the submission are.
 *
 * `activity_code` and `country` are the two exceptions, because a wrong one is
 * silent: a four-digit code and a two-letter ISO country, when present at all.
 */
class UpdateReceiptProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'trade_name' => ['nullable', 'string', 'max:150'],
            // ETA's four-digit activity code. Validated for shape, not
            // membership: their list changes, and a till that refused a newly
            // issued code would be wrong in the direction that stops a
            // restaurant trading.
            'activity_code' => ['nullable', 'string', 'regex:/^\d{4}$/'],
            // The branch as the tax authority knows it — NOT branches.code.
            'branch_code' => ['nullable', 'string', 'max:32'],
            'country' => ['nullable', 'string', 'size:2', 'alpha'],
            'governate' => ['nullable', 'string', 'max:80'],
            'region_city' => ['nullable', 'string', 'max:80'],
            'street' => ['nullable', 'string', 'max:150'],
            'building_number' => ['nullable', 'string', 'max:32'],
            'postal_code' => ['nullable', 'string', 'max:16'],
            'floor' => ['nullable', 'string', 'max:16'],
            'room' => ['nullable', 'string', 'max:16'],
            'landmark' => ['nullable', 'string', 'max:150'],
            'additional_info' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:32'],
            'header_note' => ['nullable', 'string', 'max:500'],
            'footer_note' => ['nullable', 'string', 'max:500'],
            // Optimistic concurrency, the same guard the till has: send the
            // revision you loaded and a stale save is refused rather than
            // overwriting the person who saved first. Omit it to force.
            'revision' => ['nullable', 'integer', 'min:0'],
        ];
    }

    public function prepareForValidation(): void
    {
        if ($this->filled('country')) {
            $this->merge(['country' => strtoupper((string) $this->input('country'))]);
        }
    }
}
