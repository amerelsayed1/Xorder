<?php

namespace App\Http\Controllers\Admin;

use App\Enums\RoleEnum;
use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use App\Services\RestaurantProvisioningService;
use Illuminate\Http\JsonResponse;

class RestaurantAdminController extends Controller
{
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
