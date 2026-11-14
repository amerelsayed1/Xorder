<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password as PasswordRule;

class ChangePasswordRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Any authenticated user may change their own password. The route is
        // already behind auth:jwt.
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            // Verified against the signed-in user's hash directly. The framework
            // `current_password` rule leans on the guard's user provider, which
            // the stateless JWT request guard (Auth::viaRequest) doesn't expose,
            // so check it explicitly here.
            'current_password' => [
                'required', 'string',
                function (string $attribute, mixed $value, \Closure $fail): void {
                    if (! Hash::check((string) $value, (string) $this->user()->password)) {
                        $fail(__('xorder.errors.current_password_incorrect'));
                    }
                },
            ],
            // Same policy the email reset flow enforces (PasswordResetController),
            // and must differ from the current one.
            'password' => [
                'required', 'confirmed', 'different:current_password',
                PasswordRule::min(12)->mixedCase()->numbers(),
            ],
        ];
    }
}
