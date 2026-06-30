<?php

namespace App\Http\Controllers\Auth;

use App\Enums\UserStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Resources\UserResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Sanctum SPA login: authenticate against the session guard, regenerate
     * the session, and return the user with role for client-side redirection.
     */
    public function login(LoginRequest $request): JsonResponse
    {
        $credentials = $request->only('email', 'password');
        $remember = $request->boolean('remember');

        if (! Auth::attempt($credentials, $remember)) {
            throw ValidationException::withMessages([
                'email' => __('auth.failed'),
            ]);
        }

        $user = Auth::user();

        if ($user->status !== UserStatus::ACTIVE) {
            Auth::logout();
            throw ValidationException::withMessages([
                'email' => __('xorder.errors.account_suspended'),
            ]);
        }

        // Stateful (SPA) requests have a session; guard defensively so a
        // stateless/token call never 500s on session regeneration.
        if ($request->hasSession()) {
            $request->session()->regenerate();
        }
        $user->loadMissing('restaurant');

        return response()->json([
            'data' => UserResource::make($user),
            'message' => __('xorder.messages.logged_in'),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        Auth::guard('web')->logout();
        if ($request->hasSession()) {
            $request->session()->invalidate();
            $request->session()->regenerateToken();
        }

        return response()->json(['message' => __('xorder.messages.logged_out')]);
    }

    /** Current authenticated user + restaurant context (for the SPA bootstrap). */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user()->loadMissing('restaurant');

        return response()->json(['data' => UserResource::make($user)]);
    }
}
