<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\TenantCapability;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreRoleRequest;
use App\Http\Requests\Dashboard\UpdateRoleRequest;
use App\Http\Resources\RoleResource;
use App\Models\Role;
use App\Services\TenantRoleService;
use App\Services\TenantUserService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A restaurant's own staff roles. Gated by `can:staff.manage`.
 *
 * Tenant isolation is structural: Role carries the global RestaurantScope, so
 * another restaurant's role id simply doesn't resolve here (404, not 403) and
 * every listing is already constrained to the caller's tenant.
 */
class RoleController extends Controller
{
    public function __construct(
        private readonly TenantRoleService $roles,
        private readonly TenantUserService $users,
    ) {}

    public function index(): JsonResponse
    {
        $roles = Role::query()
            ->withCount('users')
            ->orderByDesc('is_system')
            ->orderBy('name')
            ->get();

        return response()->json(['data' => RoleResource::collection($roles)]);
    }

    /**
     * The capability catalogue for the role builder: every value, its UI group,
     * and which "view" each "manage" implies. Served from the enum so the client
     * never hard-codes a list that can drift from the server's.
     */
    public function capabilities(): JsonResponse
    {
        // resource/action are sent so the role editor can lay the catalogue out
        // as a grid (one row per resource, one column per verb) instead of a
        // flat list of 27 checkboxes.
        $data = array_map(fn (TenantCapability $c) => [
            'value' => $c->value,
            'group' => $c->group(),
            'resource' => $c->resource(),
            'action' => $c->action(),
            'implies' => $c->implies()?->value,
        ], TenantCapability::cases());

        return response()->json(['data' => $data]);
    }

    public function show(Role $role): JsonResponse
    {
        return response()->json(['data' => RoleResource::make($role->loadCount('users'))]);
    }

    public function store(StoreRoleRequest $request): JsonResponse
    {
        $role = $this->roles->create($request->user(), $request->validated());

        return response()->json([
            'data' => RoleResource::make($role),
            'message' => __('xorder.messages.role_created'),
        ], 201);
    }

    public function update(Role $role, UpdateRoleRequest $request): JsonResponse
    {
        $role = $this->roles->update($request->user(), $role, $request->validated());

        return response()->json([
            'data' => RoleResource::make($role),
            'message' => __('xorder.messages.role_updated'),
        ]);
    }

    /**
     * Delete a custom role. System presets are permanent, and a role people
     * still hold must be reassigned first: users.role_id is restrictOnDelete,
     * and blanking it would leave those accounts with no capabilities at all.
     * Pass `reassign_to` (another role id in this restaurant) to move them.
     */
    public function destroy(Role $role, Request $request): JsonResponse
    {
        if ($role->is_system) {
            return response()->json(['message' => __('xorder.messages.role_system_undeletable')], 422);
        }

        $holders = $role->users()->count();

        if ($holders > 0) {
            $replacement = $this->resolveReplacement($role, $request->input('reassign_to'));

            if ($replacement === null) {
                return response()->json([
                    'message' => __('xorder.messages.role_in_use', ['count' => $holders]),
                    'users_count' => $holders,
                ], 422);
            }

            $this->users->reassignRole($role, $replacement);
        }

        $role->delete();

        return response()->json(['message' => __('xorder.messages.role_deleted')]);
    }

    /** The role to move holders onto — scoped, and never the role being deleted. */
    private function resolveReplacement(Role $role, mixed $replacementId): ?Role
    {
        $replacementId = (int) $replacementId;

        if ($replacementId <= 0 || $replacementId === $role->id) {
            return null;
        }

        // RestaurantScope keeps this inside the caller's tenant.
        return Role::find($replacementId);
    }
}
