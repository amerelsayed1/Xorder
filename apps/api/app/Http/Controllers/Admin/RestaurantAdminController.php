<?php

namespace App\Http\Controllers\Admin;

use App\Enums\RoleEnum;
use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateRestaurantAdminRequest;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use App\Services\RestaurantProvisioningService;
use Illuminate\Http\JsonResponse;

class RestaurantAdminController extends Controller
{
    /**
     * Update the restaurant admin's identity (name, login username, email).
     * Password is handled separately by resetPassword().
     */
    public function update(Restaurant $restaurant, UpdateRestaurantAdminRequest $request): JsonResponse
    {
        $admin = $restaurant->users()
            ->where('role', RoleEnum::RESTAURANT_ADMIN)
            ->first();

        if (! $admin) {
            return response()->json([
                'message' => __('xorder.messages.restaurant_admin_not_found'),
            ], 404);
        }

        $admin->fill([
            'name' => $request->input('name'),
            'username' => $request->input('username'),
            'email' => $request->input('email'),
        ])->save();

        AuditLogger::record('restaurant.admin_updated', [
            'restaurant_id' => $restaurant->id,
            'auditable' => $admin,
            'description' => sprintf('Updated admin account "%s"', $admin->name),
        ]);

        return response()->json([
            'data' => [
                'id' => $admin->id,
                'name' => $admin->name,
                'username' => $admin->username,
                'email' => $admin->email,
                'status' => $admin->status->value,
            ],
            'message' => __('xorder.messages.admin_updated'),
        ]);
    }

    /**
     * Regenerate the restaurant admin's password. The new password is emailed
     * and returned once so the Super Admin can relay it to the owner.
     */
    public function resetPassword(Restaurant $restaurant, RestaurantProvisioningService $provisioner): JsonResponse
    {
        $admin = $restaurant->users()
            ->where('role', RoleEnum::RESTAURANT_ADMIN)
            ->first();

        if (! $admin) {
            return response()->json([
                'message' => __('xorder.messages.restaurant_admin_not_found'),
            ], 404);
        }

        $password = $provisioner->resetAdminPassword($admin);

        // The password change itself is redacted from audit diffs, so record
        // the action explicitly (scoped to the restaurant tenant).
        AuditLogger::record('restaurant.admin_password_reset', [
            'restaurant_id' => $restaurant->id,
            'auditable' => $admin,
            'description' => sprintf('Reset admin password for "%s"', $admin->name),
        ]);

        return response()->json([
            'generated_password' => $password,
            'message' => __('xorder.messages.admin_password_reset'),
        ]);
    }
}
