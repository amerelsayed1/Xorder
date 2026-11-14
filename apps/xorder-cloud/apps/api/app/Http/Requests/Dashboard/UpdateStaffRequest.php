<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\UserStatus;
use App\Http\Requests\Dashboard\Concerns\GrantsTenantCapabilities;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateStaffRequest extends FormRequest
{
    use GrantsTenantCapabilities;

    public function authorize(): bool
    {
        return $this->user()?->can('staff.update') ?? false;
    }

    public function rules(): array
    {
        $tenantId = $this->user()?->restaurant_id;
        $staffId = $this->route('staff')?->id ?? 0;

        return [
            'name' => ['required', 'string', 'max:150'],
            'username' => [
                'required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/',
                Rule::unique('users', 'username')->where('restaurant_id', $tenantId)->ignore($staffId),
            ],
            'email' => ['nullable', 'email', 'max:255', Rule::unique('users', 'email')->ignore($staffId)],
            'role_id' => [
                'required', 'integer',
                Rule::exists('roles', 'id')->where('restaurant_id', $tenantId),
            ],
            'status' => ['nullable', Rule::in([UserStatus::ACTIVE->value, UserStatus::SUSPENDED->value])],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(fn (Validator $v) => $this->rejectRoleAboveSelf($v));
    }
}
