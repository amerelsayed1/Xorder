<?php

namespace App\Http\Requests\Admin;

use App\Enums\LeadStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateLeadRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Route is already gated by auth:jwt + can:leads.manage.
        return true;
    }

    public function rules(): array
    {
        return [
            'status' => ['required', Rule::in(LeadStatus::values())],
            'notes' => ['nullable', 'string', 'max:5000'],
        ];
    }
}
