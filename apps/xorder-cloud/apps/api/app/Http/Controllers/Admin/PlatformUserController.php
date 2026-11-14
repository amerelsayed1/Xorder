<?php

namespace App\Http\Controllers\Admin;

use App\Enums\RoleEnum;
use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StorePlatformUserRequest;
use App\Http\Requests\Admin\UpdatePlatformUserRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\PlatformUserService;
use Illuminate\Http\JsonResponse;

/**
 * Super-Admin-only management of platform staff users (Admin/Moderator/Sales/
 * Support). Gated by `can:platform_users.manage` — only SUPER_ADMIN holds it.
 * Never touches restaurant-scoped users; those are managed per-restaurant.
 */
class PlatformUserController extends Controller
{
    public function __construct(private readonly PlatformUserService $service) {}

    /** List platform staff users (restaurant_id null), newest first. */
    public function index(): JsonResponse
    {
        $users = User::query()
            ->whereNull('restaurant_id')
            ->orderByDesc('id')
            ->get();

        return response()->json(['data' => UserResource::collection($users)]);
    }

    public function show(User $user): JsonResponse
    {
        if ($response = $this->guardTarget($user)) {
            return $response;
        }

        return response()->json(['data' => UserResource::make($user)]);
    }

    public function store(StorePlatformUserRequest $request): JsonResponse
    {
        $result = $this->service->create($request->validated());
        $user = $result['user'];

        AuditLogger::record('platform_user.created', [
            'restaurant_id' => null,
            'auditable' => $user,
            'description' => sprintf('Created %s user "%s"', $user->role->value, $user->name),
        ]);

        return response()->json([
            'data' => UserResource::make($user),
            'generated_password' => $result['generated_password'],
            'message' => __('xorder.messages.platform_user_created'),
        ], 201);
    }

    public function update(User $user, UpdatePlatformUserRequest $request): JsonResponse
    {
        if ($response = $this->guardTarget($user)) {
            return $response;
        }

        $user = $this->service->update($user, $request->validated());

        AuditLogger::record('platform_user.updated', [
            'restaurant_id' => null,
            'auditable' => $user,
            'description' => sprintf('Updated user "%s"', $user->name),
        ]);

        return response()->json([
            'data' => UserResource::make($user),
            'message' => __('xorder.messages.platform_user_updated'),
        ]);
    }

    public function resetPassword(User $user): JsonResponse
    {
        if ($response = $this->guardTarget($user)) {
            return $response;
        }

        $password = $this->service->resetPassword($user);

        // The password change is redacted from audit diffs, so record explicitly.
        AuditLogger::record('platform_user.password_reset', [
            'restaurant_id' => null,
            'auditable' => $user,
            'description' => sprintf('Reset password for "%s"', $user->name),
        ]);

        return response()->json([
            'generated_password' => $password,
            'message' => __('xorder.messages.platform_user_password_reset'),
        ]);
    }

    public function destroy(User $user): JsonResponse
    {
        if ($response = $this->guardTarget($user)) {
            return $response;
        }

        AuditLogger::record('platform_user.deleted', [
            'restaurant_id' => null,
            'auditable' => $user,
            'description' => sprintf('Deleted user "%s"', $user->name),
        ]);

        $user->delete();

        return response()->json(['message' => __('xorder.messages.platform_user_deleted')]);
    }

    /**
     * Refuse to act on anything that isn't a manageable platform staff user:
     * a restaurant-scoped user (404 — invisible to this endpoint), a SUPER_ADMIN
     * owner account, or the caller's own account.
     */
    private function guardTarget(User $user): ?JsonResponse
    {
        // Restaurant users are out of scope for platform management — 404 so the
        // endpoint doesn't even acknowledge them.
        if ($user->restaurant_id !== null || ! $user->role->isPlatformRole()) {
            return response()->json(['message' => __('xorder.messages.platform_user_not_found')], 404);
        }

        if ($user->role === RoleEnum::SUPER_ADMIN) {
            return response()->json(['message' => __('xorder.messages.platform_user_super_admin_forbidden')], 403);
        }

        if ($user->id === request()->user()?->id) {
            return response()->json(['message' => __('xorder.messages.platform_user_self_forbidden')], 403);
        }

        return null;
    }
}
