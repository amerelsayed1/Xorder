<?php

namespace App\Http\Requests\Dashboard;

use App\Enums\UserStatus;
use App\Http\Requests\Dashboard\Concerns\GrantsTenantCapabilities;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreStaffRequest extends FormRequest
{
    use GrantsTenantCapabilities;

    public function authorize(): bool
    {
        return $this->user()?->can('staff.create') ?? false;
    }

    public function rules(): array
    {
        $tenantId = $this->user()?->restaurant_id;

        return [
            'name' => ['required', 'string', 'max:150'],
            // Username is the login and is unique per tenant, so two restaurants
            // may each have a "cashier1".
            'username' => [
                'required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/',
                Rule::unique('users', 'username')->where('restaurant_id', $tenantId),
            ],
            // Optional: floor staff log in with a username and no email. The
            // column is nullable but still globally unique, so validate it —
            // two staff sharing an address would otherwise 500 at the DB.
            'email' => ['nullable', 'email', 'max:255', Rule::unique('users', 'email')],
            'role_id' => [
                'required', 'integer',
                Rule::exists('roles', 'id')->where('restaurant_id', $tenantId),
            ],
            'status' => ['nullable', Rule::in([UserStatus::ACTIVE->value, UserStatus::SUSPENDED->value])],
            // Optional — a strong password is generated when omitted.
            'password' => ['nullable', 'string', 'min:8', 'max:255'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(fn (Validator $v) => $this->rejectRoleAboveSelf($v));
    }
}
