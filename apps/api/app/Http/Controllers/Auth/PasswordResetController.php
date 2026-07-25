<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;

class PasswordResetController extends Controller
{
    public function forgot(Request $request): JsonResponse
    {
        $request->validate(['email' => ['required', 'email']]);

        // Always return the same response to avoid user enumeration.
        Password::sendResetLink($request->only('email'));

        return response()->json([
            'message' => __('xorder.messages.reset_link_sent'),
        ]);
    }

    public function reset(Request $request): JsonResponse
    {
        $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'email'],
            // Human-chosen password on reset: require length + complexity.
            // (`uncompromised()` — a HIBP breach check — is a worthwhile further
            // step but adds a network dependency, so it is left as an opt-in.)
            'password' => ['required', 'confirmed', PasswordRule::min(12)->mixedCase()->numbers()],
        ]);

        $status = Password::reset(
            $request->only('email', 'password', 'password_confirmation', 'token'),
            function ($user, $password) {
                $user->forceFill([
                    'password' => $password, // hashed by the 'hashed' cast
                    // Invalidate every JWT issued before this reset (guard checks
                    // token iat against password_changed_at).
                    'password_changed_at' => now(),
                    'remember_token' => Str::random(60),
                ])->save();
            }
        );

        if ($status !== Password::PasswordReset) {
            // Deliberately generic: the broker distinguishes "no such user"
            // (passwords.user) from "bad token" (passwords.token), which leaks
            // whether an email is registered. Collapse both into one message.
            return response()->json([
                'message' => __('xorder.errors.password_reset_failed'),
            ], 422);
        }

        return response()->json(['message' => __('xorder.messages.password_reset')]);
    }
}
