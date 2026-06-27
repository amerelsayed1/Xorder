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
        return [
            'subscription_status' => ['required', Rule::enum(SubscriptionStatus::class)],
            'subscription_plan' => ['nullable', 'string', 'max:100'],
            'subscription_start_date' => ['nullable', 'date'],
            'subscription_end_date' => ['nullable', 'date', 'after_or_equal:subscription_start_date'],
        ];
    }
}
