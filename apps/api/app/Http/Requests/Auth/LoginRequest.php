<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;

class LoginRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'username' => ['required', 'string', 'max:150'],
            'password' => ['required', 'string'],
            'remember' => ['sometimes', 'boolean'],
            // Optional tenant hint: the restaurant subdomain the SPA is serving.
            // Lets tenant login resolve the account without a trustworthy Host
            // header (dev proxy / decoupled API origin). Omitted by the
            // super-admin portal, which resolves to no tenant.
            'restaurant' => ['sometimes', 'nullable', 'string', 'max:255'],
        ];
    }

    /** Usernames are case-insensitive; normalise before matching. */
    protected function prepareForValidation(): void
    {
        if ($this->has('username')) {
            $this->merge(['username' => mb_strtolower(trim((string) $this->input('username')))]);
        }
    }
}
