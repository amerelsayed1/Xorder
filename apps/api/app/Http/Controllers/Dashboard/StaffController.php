<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\RoleEnum;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreStaffRequest;
use App\Http\Requests\Dashboard\UpdateStaffRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\PlanLimitService;
use App\Services\TenantUserService;
use Illuminate\Http\JsonResponse;

/**
 * Staff accounts inside one restaurant. Gated by `can:staff.manage`.
 *
 * Unlike every other tenant controller, this one cannot lean on the global
 * RestaurantScope: {@see User} deliberately does NOT carry it (adding it would
 * break login lookups and Super Admin queries). So the tenant boundary is
 * enforced by hand here — every query filters on the caller's restaurant_id and
 * guardTarget() re-checks the bound model, exactly as the platform-side
 * PlatformUserController does.
 *
 * The owner account (RESTAURANT_ADMIN) is out of scope: it is provisioned and
 * reset by the Super Admin, and is invisible to this endpoint so that a manager
 * with `staff.manage` can never take it over.
 */
class StaffController extends Controller
{
    public function __construct(private readonly TenantUserService $service) {}

    /**
     * Everyone who can sign in to this restaurant — the owner included.
     *
     * The owner is listed but never actionable: they hold every capability
     * implicitly and no Role governs them, so the row is informational. An
     * Employees screen that hid the one person who is always there read as
     * broken, especially for a restaurant that has not added staff yet.
     *
     * Only the listing widens. Every write path still runs through
     * {@see guardTarget()}, which 404s on anything that is not a staff account
     * of the caller's own tenant — so no request can edit, suspend or delete
     * the account that owns the restaurant, whatever the UI offers.
     */
    public function index(): JsonResponse
    {
        $people = User::query()
            ->where('restaurant_id', request()->user()?->restaurant_id)
            ->whereIn('role', [RoleEnum::RESTAURANT_ADMIN, RoleEnum::RESTAURANT_STAFF])
            ->with('tenantRole')
            // Owner first, then newest staff.
            ->orderByRaw('CASE WHEN role = ? THEN 0 ELSE 1 END', [RoleEnum::RESTAURANT_ADMIN->value])
            ->orderByDesc('id')
            ->get();

        return response()->json(['data' => UserResource::collection($people)]);
    }

    public function show(User $staff): JsonResponse
    {
        if ($response = $this->guardTarget($staff)) {
            return $response;
        }

        return response()->json(['data' => UserResource::make($staff->load('tenantRole'))]);
    }

    public function store(StoreStaffRequest $request, PlanLimitService $limits): JsonResponse
    {
        // Seat cap from the plan. Checked here rather than in the FormRequest so
        // the tenant gets "your plan allows N" instead of a generic validation
        // error, matching how the item and branch caps report.
        if (($limit = $limits->staffLimitReached($request->user()->restaurant)) !== null) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_staff', ['limit' => $limit]),
            ], 422);
        }

        $result = $this->service->create($request->user(), $request->validated());
        $user = $result['user'];

        return response()->json([
            'data' => UserResource::make($user),
            'generated_password' => $result['generated_password'],
            'message' => __('xorder.messages.staff_created'),
        ], 201);
    }

    public function update(User $staff, UpdateStaffRequest $request): JsonResponse
    {
        if ($response = $this->guardTarget($staff)) {
            return $response;
        }

        $staff = $this->service->update($staff, $request->validated());

        return response()->json([
            'data' => UserResource::make($staff),
            'message' => __('xorder.messages.staff_updated'),
        ]);
    }

    public function resetPassword(User $staff): JsonResponse
    {
        if ($response = $this->guardTarget($staff)) {
            return $response;
        }

        $password = $this->service->resetPassword($staff);

        // The password change is redacted from audit diffs, so record it plainly.
        AuditLogger::record('staff.password_reset', [
            'restaurant_id' => $staff->restaurant_id,
            'auditable' => $staff,
            'description' => sprintf('Reset password for "%s"', $staff->name),
        ]);

        return response()->json([
            'generated_password' => $password,
            'message' => __('xorder.messages.staff_password_reset'),
        ]);
    }

    public function destroy(User $staff): JsonResponse
    {
        if ($response = $this->guardTarget($staff)) {
            return $response;
        }

        $staff->delete();

        return response()->json(['message' => __('xorder.messages.staff_deleted')]);
    }

    /**
     * Staff accounts of the caller's restaurant — never the owner, never
     * another tenant. Used by every path that acts on an account; the listing
     * above deliberately casts wider.
     */
    private function scoped()
    {
        return User::query()
            ->where('restaurant_id', request()->user()?->restaurant_id)
            ->where('role', RoleEnum::RESTAURANT_STAFF);
    }

    /**
     * Refuse to act on anything that isn't a staff account of the caller's own
     * restaurant. 404 rather than 403 throughout: cross-tenant ids and the owner
     * account are not merely forbidden, they are invisible.
     */
    private function guardTarget(User $staff): ?JsonResponse
    {
        $actor = request()->user();

        $sameTenant = $actor?->restaurant_id !== null
            && $staff->restaurant_id === $actor->restaurant_id;

        if (! $sameTenant || $staff->role !== RoleEnum::RESTAURANT_STAFF) {
            return response()->json(['message' => __('xorder.messages.staff_not_found')], 404);
        }

        if ($staff->id === $actor->id) {
            return response()->json(['message' => __('xorder.messages.staff_self_forbidden')], 403);
        }

        return null;
    }
}
