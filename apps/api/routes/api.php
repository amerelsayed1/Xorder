<?php

use App\Http\Controllers\Admin\InsightsController as AdminInsightsController;
use App\Http\Controllers\Admin\LandingContentController as AdminLandingContentController;
use App\Http\Controllers\Admin\LeadController as AdminLeadController;
use App\Http\Controllers\Admin\MenuParserController as AdminMenuParserController;
use App\Http\Controllers\Admin\PlanController as AdminPlanController;
use App\Http\Controllers\Admin\RestaurantAdminController as AdminRestaurantAdminController;
use App\Http\Controllers\Admin\RestaurantController as AdminRestaurantController;
use App\Http\Controllers\Admin\RestaurantQrController as AdminQrController;
use App\Http\Controllers\Admin\RestaurantStatusController;
use App\Http\Controllers\Admin\SubscriptionController;
use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\Auth\PasswordResetController;
use App\Http\Controllers\Dashboard\BranchController;
use App\Http\Controllers\Dashboard\CategoryController;
use App\Http\Controllers\Dashboard\ComboController;
use App\Http\Controllers\Dashboard\DashboardQrController;
use App\Http\Controllers\Dashboard\InsightsController as DashboardInsightsController;
use App\Http\Controllers\Dashboard\CustomerController;
use App\Http\Controllers\Dashboard\MenuImportController;
use App\Http\Controllers\Dashboard\PushTokenController;
use App\Http\Controllers\Dashboard\MenuItemController;
use App\Http\Controllers\Dashboard\OrderController as DashboardOrderController;
use App\Http\Controllers\Dashboard\RestaurantProfileController;
use App\Http\Controllers\Dashboard\StatsController;
use App\Http\Controllers\Public\LandingContentController as PublicLandingContentController;
use App\Http\Controllers\Public\LeadController as PublicLeadController;
use App\Http\Controllers\Public\PublicMenuApiController;
use App\Http\Controllers\Public\PublicOrderController;
use App\Http\Controllers\Public\RestaurantBrandingController;
use App\Http\Controllers\Public\RestaurantQrController as PublicRestaurantQrController;
use App\Http\Controllers\Public\SignupController;
use App\Http\Controllers\UploadController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Authentication
|--------------------------------------------------------------------------
*/
Route::prefix('auth')->group(function () {
    Route::post('login', [AuthController::class, 'login'])->middleware('throttle:10,1');
    Route::post('forgot-password', [PasswordResetController::class, 'forgot'])->middleware('throttle:5,1');
    Route::post('reset-password', [PasswordResetController::class, 'reset'])->middleware('throttle:5,1');

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
    });
});

/*
|--------------------------------------------------------------------------
| Super Admin  (requires SUPER_ADMIN)
|--------------------------------------------------------------------------
*/
Route::prefix('admin')
    ->middleware(['auth:sanctum', 'role:SUPER_ADMIN'])
    ->group(function () {
        Route::get('insights', [AdminInsightsController::class, 'index']);
        Route::get('restaurants', [AdminRestaurantController::class, 'index']);
        Route::post('restaurants', [AdminRestaurantController::class, 'store']);
        Route::get('restaurants/{restaurant}', [AdminRestaurantController::class, 'show']);
        Route::put('restaurants/{restaurant}', [AdminRestaurantController::class, 'update']);
        Route::delete('restaurants/{restaurant}', [AdminRestaurantController::class, 'destroy']);
        Route::patch('restaurants/{restaurant}/status', [RestaurantStatusController::class, 'update']);
        Route::patch('restaurants/{restaurant}/subscription', [SubscriptionController::class, 'update']);
        Route::post('restaurants/{restaurant}/admin/reset-password', [AdminRestaurantAdminController::class, 'resetPassword'])
            ->middleware('throttle:10,1');
        Route::get('restaurants/{restaurant}/qr', [AdminQrController::class, 'show']);
        Route::get('restaurants/{restaurant}/qr/download', [AdminQrController::class, 'download']);

        // Subscription plans catalog
        Route::get('plans', [AdminPlanController::class, 'index']);
        Route::post('plans', [AdminPlanController::class, 'store']);
        Route::get('plans/{plan}', [AdminPlanController::class, 'show']);
        Route::put('plans/{plan}', [AdminPlanController::class, 'update']);
        Route::delete('plans/{plan}', [AdminPlanController::class, 'destroy']);

        // Landing page content (CMS)
        Route::get('landing-content', [AdminLandingContentController::class, 'show']);
        Route::put('landing-content', [AdminLandingContentController::class, 'update']);

        // Landing page leads (sales inbox)
        Route::get('leads', [AdminLeadController::class, 'index']);
        Route::get('leads/export', [AdminLeadController::class, 'export']);
        Route::patch('leads/{lead}', [AdminLeadController::class, 'update']);

        // Menu image parser
        Route::post('menu-parser/parse', [AdminMenuParserController::class, 'parse']);
    });

/*
|--------------------------------------------------------------------------
| Restaurant Dashboard  (requires RESTAURANT_ADMIN)
|--------------------------------------------------------------------------
| Writes additionally pass through `subscription.writable`.
*/
Route::prefix('dashboard')
    ->middleware(['auth:sanctum', 'role:RESTAURANT_ADMIN'])
    ->group(function () {
        // Reads
        Route::get('restaurant', [RestaurantProfileController::class, 'show']);
        Route::get('stats', [StatsController::class, 'index']);
        Route::get('insights', [DashboardInsightsController::class, 'index']);
        Route::get('branches', [BranchController::class, 'index']);
        Route::get('combos', [ComboController::class, 'index']);
        Route::get('categories', [CategoryController::class, 'index']);
        Route::get('categories/{category}', [CategoryController::class, 'show']);
        Route::get('items', [MenuItemController::class, 'index']);
        Route::get('items/{item}', [MenuItemController::class, 'show']);
        Route::get('customers', [CustomerController::class, 'index']);
        Route::get('customers/{customer}', [CustomerController::class, 'show']);

        // Push-notification device tokens (not subscription-gated).
        Route::post('push/token', [PushTokenController::class, 'store']);
        Route::delete('push/token', [PushTokenController::class, 'destroy']);
        Route::get('qr', [DashboardQrController::class, 'show']);
        Route::get('qr/download', [DashboardQrController::class, 'download']);

        // Orders — deliberately NOT behind subscription.writable: a restaurant
        // whose subscription just expired must still be able to process the
        // orders that already came in.
        Route::get('orders', [DashboardOrderController::class, 'index']);
        Route::get('orders/new-count', [DashboardOrderController::class, 'newCount']);
        Route::patch('orders/{order}/status', [DashboardOrderController::class, 'updateStatus']);

        // Writes (subscription-gated)
        Route::middleware('subscription.writable')->group(function () {
            Route::put('restaurant', [RestaurantProfileController::class, 'update']);

            Route::post('branches', [BranchController::class, 'store']);
            Route::put('branches/{branch}', [BranchController::class, 'update']);
            Route::patch('branches/{branch}/status', [BranchController::class, 'toggleOpen']);
            Route::delete('branches/{branch}', [BranchController::class, 'destroy']);

            Route::post('combos', [ComboController::class, 'store']);
            Route::put('combos/{combo}', [ComboController::class, 'update']);
            Route::patch('combos/{combo}/status', [ComboController::class, 'toggleStatus']);
            Route::delete('combos/{combo}', [ComboController::class, 'destroy']);

            Route::post('categories', [CategoryController::class, 'store']);
            Route::patch('categories/reorder', [CategoryController::class, 'reorder']);
            Route::put('categories/{category}', [CategoryController::class, 'update']);
            Route::patch('categories/{category}/status', [CategoryController::class, 'toggleStatus']);
            Route::delete('categories/{category}', [CategoryController::class, 'destroy']);

            Route::post('items/import', [MenuImportController::class, 'import']);
            Route::post('items', [MenuItemController::class, 'store']);
            Route::patch('items/reorder', [MenuItemController::class, 'reorder']);
            Route::put('items/{item}', [MenuItemController::class, 'update']);
            Route::patch('items/{item}/availability', [MenuItemController::class, 'toggleAvailability']);
            Route::delete('items/{item}', [MenuItemController::class, 'destroy']);
        });
    });

/*
|--------------------------------------------------------------------------
| Uploads  (any authenticated admin)
|--------------------------------------------------------------------------
*/
Route::post('uploads/image', [UploadController::class, 'store'])
    ->middleware(['auth:sanctum', 'throttle:60,1']);

/*
|--------------------------------------------------------------------------
| Public  (no auth)
|--------------------------------------------------------------------------
*/
Route::get('public/restaurants/{slug}/menu', [PublicMenuApiController::class, 'show'])
    ->middleware('throttle:120,1');

Route::get('public/landing-content', [PublicLandingContentController::class, 'show'])
    ->middleware('throttle:120,1');

// Self-serve signup — 404s unless SELF_SERVE_SIGNUP=true (see config/platform.php).
Route::post('public/signup', [SignupController::class, 'store'])
    ->middleware('throttle:5,10');

// A human submits this form once, maybe twice after a validation error.
// 5 per 10 minutes per IP caps sustained spam at ~30/hour instead of 600.
Route::post('public/leads', [PublicLeadController::class, 'store'])
    ->middleware('throttle:5,10');

// Guest order recording (pre-WhatsApp handoff). Kept loose enough for many
// diners behind one restaurant-WiFi IP.
Route::post('public/restaurants/{slug}/orders', [PublicOrderController::class, 'store'])
    ->middleware('throttle:20,1');

Route::get('public/restaurants/{slug}/branding', [RestaurantBrandingController::class, 'show'])
    ->middleware('throttle:120,1');

Route::get('public/restaurants/{slug}/qr', [PublicRestaurantQrController::class, 'show'])
    ->middleware('throttle:120,1');
