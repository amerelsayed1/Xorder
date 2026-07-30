<?php

namespace App\Http\Requests\Admin;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdatePlatformUserRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('platform_users.manage') ?? false;
    }

    public function rules(): array
    {
        $user = $this->route('user');
        $userId = $user?->id ?? 0;

        return [
            'name' => ['required', 'string', 'max:150'],
            'username' => [
                'required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/',
                Rule::unique('users', 'username')->whereNull('restaurant_id')->ignore($userId),
            ],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($userId)],
            'role' => ['required', Rule::in(RoleEnum::assignable())],
            'status' => ['nullable', Rule::in([UserStatus::ACTIVE->value, UserStatus::SUSPENDED->value])],
        ];
    }
}
