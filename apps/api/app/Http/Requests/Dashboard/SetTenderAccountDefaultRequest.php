<?php

namespace App\Http\Requests\Dashboard;

use App\Models\FinancialAccount;
use App\Models\TenderType;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * XORD-015: set (or clear, with a null account) the account a payment method
 * pays into at one branch; a null branch is the business-wide fallback.
 *
 * The gate is the route's `can:finance.accounts` — deliberately NOT
 * `settings.update`, so a person who may edit payment methods cannot redirect
 * where the money goes. Every id is looked up inside the caller's restaurant.
 * An account may be the default only if it is active and either shared by the
 * whole business or tied to the very branch the default is for; a business-wide
 * default must therefore be a shared account. And its kind must be one the
 * payment method pays into (`FinancialAccount::KINDS_FOR_TENDER`).
 */
class SetTenderAccountDefaultRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenant = $this->user()->restaurant_id;

        return [
            'tender_type_id' => [
                'required', 'integer',
                Rule::exists('tender_types', 'id')->where('restaurant_id', $tenant),
            ],
            'branch_id' => [
                'nullable', 'integer',
                Rule::exists('branches', 'id')->where('restaurant_id', $tenant),
            ],
            'financial_account_id' => [
                'nullable', 'integer',
                Rule::exists('financial_accounts', 'id')->where('restaurant_id', $tenant),
            ],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $accountId = $this->input('financial_account_id');

            if ($accountId === null || $validator->errors()->isNotEmpty()) {
                return;
            }

            $account = FinancialAccount::find($accountId);
            $branchId = $this->input('branch_id');

            if (! $account || ! $account->is_active) {
                $validator->errors()->add('financial_account_id', __('xorder.validation.account_inactive'));

                return;
            }

            if ($account->branch_id !== null && (int) $account->branch_id !== (int) $branchId) {
                $validator->errors()->add('financial_account_id', __('xorder.validation.account_other_branch'));

                return;
            }

            // The account's kind must be one this payment method pays into:
            // cash into a cash account, a card (or external terminal) into a
            // bank. The method id was already checked against the caller's
            // restaurant by the rules above.
            $method = TenderType::find($this->input('tender_type_id'));

            if ($method && ! $account->fitsTender($method->kind)) {
                $validator->errors()->add('financial_account_id', __('xorder.validation.account_kind_mismatch'));
            }
        }];
    }

    public function messages(): array
    {
        return [
            'tender_type_id.exists' => __('xorder.validation.account_tender'),
            'branch_id.exists' => __('xorder.validation.account_branch'),
            'financial_account_id.exists' => __('xorder.validation.account_missing'),
        ];
    }
}
