<?php

namespace App\Http\Requests\Admin;

use App\Enums\RoleEnum;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateRestaurantAdminRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->isSuperAdmin() ?? false;
    }

    public function rules(): array
    {
        $restaurant = $this->route('restaurant');
        $admin = $restaurant->users()
            ->where('role', RoleEnum::RESTAURANT_ADMIN)
            ->first();
        $adminId = $admin?->id ?? 0;

        return [
            'name' => ['required', 'string', 'max:150'],
            // Username is the login and unique PER TENANT (DB index on
            // COALESCE(restaurant_id, 0), username); scope the uniqueness check
            // to this restaurant and ignore the admin's own row.
            'username' => [
                'required', 'string', 'min:3', 'max:150', 'regex:/^[a-z0-9._-]+$/',
                Rule::unique('users', 'username')
                    ->where('restaurant_id', $restaurant->id)
                    ->ignore($adminId),
            ],
            // Email is globally unique; ignore the admin's own row.
            'email' => [
                'nullable', 'email', 'max:255',
                Rule::unique('users', 'email')->ignore($adminId),
            ],
        ];
    }
}
