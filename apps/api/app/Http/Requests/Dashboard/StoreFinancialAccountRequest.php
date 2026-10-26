<?php

namespace App\Http\Requests\Dashboard;

use App\Models\FinancialAccount;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * XORD-015: add or edit a financial account (cash, bank, wallet).
 *
 * The gate is the route's `can:finance.accounts`. Everything an id points at is
 * looked up inside the caller's own restaurant, so another tenant's branch is
 * a validation failure and never a hint that it exists. `currency` is not an
 * input: the server sets it from the restaurant.
 */
class StoreFinancialAccountRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        $merge = [];

        foreach (['name', 'reference_label'] as $key) {
            if (is_string($this->input($key))) {
                $merge[$key] = trim($this->input($key));
            }
        }

        if (($merge['reference_label'] ?? null) === '') {
            $merge['reference_label'] = null;
        }

        $this->merge($merge);
    }

    /**
     * Nine or more digits in a row (up to three non-letter, non-digit characters
     * between them), in ANY script: Arabic-Indic and full-width digits count, so
     * a number typed on an Arabic keyboard is caught like an ASCII one. A
     * heuristic against an account number or IBAN being stored by accident, not
     * a guarantee: a number split by letters gets through. The till applies the
     * same pattern (`AccountRules`).
     */
    public const LOOKS_LIKE_NUMBER = '/\p{Nd}(?:[^\p{L}\p{Nd}]{0,3}\p{Nd}){8,}/u';

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;
        $current = $this->route('financialAccount');

        return [
            'name' => [
                'required', 'string', 'max:120', 'not_regex:'.self::LOOKS_LIKE_NUMBER,
                Rule::unique('financial_accounts', 'name')
                    ->where('restaurant_id', $tenant)
                    ->ignore($current?->id),
            ],
            'kind' => ['required', Rule::in(FinancialAccount::KINDS)],
            'branch_id' => [
                'nullable', 'integer',
                Rule::exists('branches', 'id')->where('restaurant_id', $tenant),
            ],
            // A short human hint such as "CIB 4521". Never an account number:
            // nine or more digits in a row (spaces and dashes allowed between
            // them) is refused, so a full number or IBAN cannot be stored here.
            'reference_label' => ['nullable', 'string', 'max:40', 'not_regex:'.self::LOOKS_LIKE_NUMBER],
            // `sometimes`, not `nullable`: both columns are NOT NULL, so an
            // explicit null is a validation error and not a database one.
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:100000'],
        ];
    }

    /**
     * "Cash" and "cash" are the same account to a person, so the name is also
     * compared without case (the unique key is exact on both engines).
     */
    public function after(): array
    {
        return [function (Validator $validator): void {
            $name = $this->input('name');

            if (! is_string($name) || $name === '' || $validator->errors()->has('name')) {
                return;
            }

            $current = $this->route('financialAccount');
            $clash = FinancialAccount::query()
                ->whereRaw('lower(name) = ?', [mb_strtolower($name)])
                ->when($current, fn ($q) => $q->where('id', '!=', $current->id))
                ->exists();

            if ($clash) {
                $validator->errors()->add('name', __('xorder.validation.account_name_taken'));
            }
        }];
    }

    public function messages(): array
    {
        return [
            'name.unique' => __('xorder.validation.account_name_taken'),
            'branch_id.exists' => __('xorder.validation.account_branch'),
            'reference_label.not_regex' => __('xorder.validation.account_reference'),
            'name.not_regex' => __('xorder.validation.account_name_number'),
        ];
    }
}
