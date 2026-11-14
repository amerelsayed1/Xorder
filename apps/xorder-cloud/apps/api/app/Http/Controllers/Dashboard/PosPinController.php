<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\SetPosPinRequest;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\PosConfigVersion;
use App\Support\PosPin;
use Illuminate\Http\JsonResponse;

/**
 * POS-BE-024: the till-unlock PIN, distinct from the dashboard password.
 *
 * Write-only by construction: the response says pin_set true/false and nothing
 * else, ever. The verifier travels on exactly one wire — the bootstrap
 * staff[] block, behind the device credential.
 *
 * Authorization deviates from StaffController's guard on purpose: a user may
 * set THEIR OWN pin (guardTarget would 403 self), and the OWNER may carry a
 * pin too (guardTarget hides owners). staff.update governs setting anyone
 * else's. Cross-tenant stays 404-shaped, as everywhere.
 */
class PosPinController extends Controller
{
    public function update(SetPosPinRequest $request, User $staff): JsonResponse
    {
        if ($response = $this->guard($staff)) {
            return $response;
        }

        $pair = PosPin::make($request->validated('pin'));

        // forceFill: pos_pin_salt/hash are deliberately not fillable, the
        // users.role discipline.
        $staff->forceFill([
            'pos_pin_salt' => $pair['salt'],
            'pos_pin_hash' => $pair['hash'],
        ])->save();

        PosConfigVersion::bump($staff->restaurant_id);

        // The action, never the PIN — not even its length.
        AuditLogger::record('staff.pos_pin_set', [
            'restaurant_id' => $staff->restaurant_id,
            'auditable' => $staff,
            'description' => sprintf('POS PIN set for "%s"', $staff->name),
        ]);

        return response()->json(['pin_set' => true, 'message' => __('xorder.messages.pos_pin_set')]);
    }

    /** Clearing locks this cashier out of every till at its next sync. */
    public function destroy(User $staff): JsonResponse
    {
        if ($response = $this->guard($staff)) {
            return $response;
        }

        $staff->forceFill(['pos_pin_salt' => null, 'pos_pin_hash' => null])->save();

        PosConfigVersion::bump($staff->restaurant_id);

        AuditLogger::record('staff.pos_pin_cleared', [
            'restaurant_id' => $staff->restaurant_id,
            'auditable' => $staff,
            'description' => sprintf('POS PIN cleared for "%s"', $staff->name),
        ]);

        return response()->json(['pin_set' => false, 'message' => __('xorder.messages.pos_pin_cleared')]);
    }

    private function guard(User $staff): ?JsonResponse
    {
        $actor = request()->user();

        $sameTenant = $actor?->restaurant_id !== null
            && $staff->restaurant_id === $actor->restaurant_id;
        $tenantAccount = in_array($staff->role, [RoleEnum::RESTAURANT_ADMIN, RoleEnum::RESTAURANT_STAFF], true);

        if (! $sameTenant || ! $tenantAccount) {
            return response()->json(['message' => __('xorder.messages.staff_not_found')], 404);
        }

        $isSelf = $staff->id === $actor->id;

        if (! $isSelf && ! $actor->holdsTenantCapability(TenantCapability::STAFF_UPDATE)) {
            return response()->json(['message' => __('xorder.errors.no_access')], 403);
        }

        // Nobody but the owner touches the owner's pin.
        if (! $isSelf && $staff->role === RoleEnum::RESTAURANT_ADMIN) {
            return response()->json(['message' => __('xorder.messages.staff_not_found')], 404);
        }

        return null;
    }
}
