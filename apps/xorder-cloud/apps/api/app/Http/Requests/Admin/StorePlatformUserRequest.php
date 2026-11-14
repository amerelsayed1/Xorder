<?php

namespace App\Http\Requests\Admin;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StorePlatformUserRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('platform_users.manage') ?? false;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            // Username is the login. Platform users share "tenant 0"
            // (restaurant_id null) in the per-tenant unique index, so scope the
            // uniqueness check to platform users.
            'username' => [
                'required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/',
                Rule::unique('users', 'username')->whereNull('restaurant_id'),
            ],
            // Email is globally unique across all users.
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'role' => ['required', Rule::in(RoleEnum::assignable())],
            'status' => ['nullable', Rule::in([UserStatus::ACTIVE->value, UserStatus::SUSPENDED->value])],
            // Optional — a strong password is generated when omitted.
            'password' => ['nullable', 'string', 'min:8', 'max:255'],
        ];
    }
}
