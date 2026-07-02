<?php

namespace App\Http\Requests\Admin;

use App\Enums\SubscriptionStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateSubscriptionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        // Expiry insights ("expiring in 7/30 days", "past end date") only see
        // subscriptions that have an end date, so ACTIVE and TRIAL must carry one.
        return [
            'subscription_status' => ['required', Rule::enum(SubscriptionStatus::class)],
            'subscription_plan' => ['nullable', 'string', 'max:100'],
            'subscription_start_date' => [
                'nullable',
                Rule::requiredIf(fn () => $this->input('subscription_status') === SubscriptionStatus::ACTIVE->value),
                'date',
            ],
            'subscription_end_date' => [
                'nullable',
                Rule::requiredIf(fn () => in_array($this->input('subscription_status'), [
                    SubscriptionStatus::ACTIVE->value,
                    SubscriptionStatus::TRIAL->value,
                ], true)),
                'date',
                'after_or_equal:subscription_start_date',
            ],
        ];
    }

    public function messages(): array
    {
        return [
            'subscription_start_date.required' => __('xorder.validation.subscription_start_date_required'),
            'subscription_end_date.required' => __('xorder.validation.subscription_end_date_required'),
        ];
    }
}
