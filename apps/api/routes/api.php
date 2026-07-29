<?php

use App\Http\Controllers\Admin\AuditLogController as AdminAuditLogController;
use App\Http\Controllers\Admin\InsightsController as AdminInsightsController;
use App\Http\Controllers\Admin\LandingContentController as AdminLandingContentController;
use App\Http\Controllers\Admin\LeadController as AdminLeadController;
use App\Http\Controllers\Admin\PlanController as AdminPlanController;
use App\Http\Controllers\Admin\RestaurantAdminController as AdminRestaurantAdminController;
use App\Http\Controllers\Admin\RestaurantController as AdminRestaurantController;
use App\Http\Controllers\Admin\RestaurantQrController as AdminQrController;
use App\Http\Controllers\Admin\RestaurantStatusController;
use App\Http\Controllers\Admin\SubscriptionController;
use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\Auth\PasswordResetController;
use App\Http\Controllers\Dashboard\BillRequestController;
use App\Http\Controllers\Dashboard\BranchController;
use App\Http\Controllers\Dashboard\CategoryController;
use App\Http\Controllers\Dashboard\ComboController;
use App\Http\Controllers\Dashboard\CustomerController;
use App\Http\Controllers\Dashboard\DashboardQrController;
use App\Http\Controllers\Dashboard\DiningAreaController;
use App\Http\Controllers\Dashboard\InsightsController as DashboardInsightsController;
use App\Http\Controllers\Dashboard\MapLinkController;
use App\Http\Controllers\Dashboard\MenuExportController;
use App\Http\Controllers\Dashboard\MenuImportController;
use App\Http\Controllers\Dashboard\MenuItemController;
use App\Http\Controllers\Dashboard\NotificationController;
use App\Http\Controllers\Dashboard\OrderController as DashboardOrderController;
use App\Http\Controllers\Dashboard\PulseController;
use App\Http\Controllers\Dashboard\PushTokenController;
use App\Http\Controllers\Dashboard\ReportController;
use App\Http\Controllers\Dashboard\RestaurantProfileController;
use App\Http\Controllers\Dashboard\ReviewController;
use App\Http\Controllers\Dashboard\StatsController;
use App\Http\Controllers\Dashboard\TableController;
use App\Http\Controllers\Public\LandingContentController as PublicLandingContentController;
use App\Http\Controllers\Public\LeadController as PublicLeadController;
use App\Http\Controllers\Public\PublicBillRequestController;
use App\Http\Controllers\Public\PublicMenuApiController;
use App\Http\Controllers\Public\PublicOrderController;
use App\Http\Controllers\Public\PublicReviewController;
use App\Http\Controllers\Public\PublicTableController;
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
    Route::post('login', [AuthController::class, 'login'])->middleware('throttle:login');
    Route::post('forgot-password', [PasswordResetController::class, 'forgot'])->middleware('throttle:5,1');
    Route::post('reset-password', [PasswordResetController::class, 'reset'])->middleware('throttle:5,1');

    Route::middleware('auth:jwt')->group(function () {
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
    ->middleware(['auth:jwt', 'role:SUPER_ADMIN'])
    ->group(function () {
        Route::get('insights', [AdminInsightsController::class, 'index']);
        Route::get('restaurants', [AdminRestaurantController::class, 'index']);
        Route::get('restaurants/stats', [AdminRestaurantController::class, 'stats']);
        Route::post('restaurants', [AdminRestaurantController::class, 'store']);
        Route::get('restaurants/{restaurant}', [AdminRestaurantController::class, 'show']);
        Route::put('restaurants/{restaurant}', [AdminRestaurantController::class, 'update']);
        Route::delete('restaurants/{restaurant}', [AdminRestaurantController::class, 'destroy']);
        Route::patch('restaurants/{restaurant}/status', [RestaurantStatusController::class, 'update']);
        Route::patch('restaurants/{restaurant}/subscription', [SubscriptionController::class, 'update']);
        Route::patch('restaurants/{restaurant}/admin', [AdminRestaurantAdminController::class, 'update']);
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

        // Audit trail — read-only activity log across all tenants.
        Route::get('audit-logs', [AdminAuditLogController::class, 'index']);
        Route::get('audit-logs/filters', [AdminAuditLogController::class, 'filters']);
    });

/*
|--------------------------------------------------------------------------
| Restaurant Dashboard  (requires RESTAURANT_ADMIN)
|--------------------------------------------------------------------------
| Writes additionally pass through `subscription.writable`.
*/
Route::prefix('dashboard')
    ->middleware(['auth:jwt', 'role:RESTAURANT_ADMIN'])
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
        // Export the menu to CSV/XLSX. A read — deliberately NOT behind
        // subscription.writable, so a read-only tenant can still get their data
        // out. Registered before items/{item} so "export" isn't matched as an id.
        Route::get('items/export', [MenuExportController::class, 'export']);
        Route::get('items/{item}', [MenuItemController::class, 'show']);
        // Customer database — gated on the customer_tracking feature (Restaurant
        // Pro). WhatsApp-only plans never build a customer list.
        Route::middleware('feature:customer_tracking')->group(function () {
            Route::get('customers', [CustomerController::class, 'index']);
            Route::get('customers/{customer}', [CustomerController::class, 'show']);
        });

        // Push-notification device tokens (not subscription-gated).
        Route::post('push/token', [PushTokenController::class, 'store']);
        Route::delete('push/token', [PushTokenController::class, 'destroy']);

        // Consolidated dashboard heartbeat: new-order + bill-request + unread
        // notification counts in one ETag'd request, so the shell polls once
        // instead of three times. Counts respect each feature gate internally.
        Route::get('pulse', [PulseController::class, 'index']);

        // In-app notification centre. Not subscription- or feature-gated: every
        // admin keeps their inbox even on a lapsed plan, and notifications span
        // multiple features (orders, bill requests, reviews, subscription).
        Route::get('notifications', [NotificationController::class, 'index']);
        Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
        Route::post('notifications/read-all', [NotificationController::class, 'markAllRead']);
        Route::patch('notifications/{notification}/read', [NotificationController::class, 'markRead']);
        Route::get('qr', [DashboardQrController::class, 'show']);
        Route::get('qr/download', [DashboardQrController::class, 'download']);

        // Turn a pasted Google Maps link (or share short link) into lat/lng for
        // the profile form. A stateless helper — not subscription-gated, since it
        // writes nothing; the resolved coordinates are saved via PUT restaurant.
        Route::post('geo/resolve-map-link', [MapLinkController::class, 'resolve']);

        // Order management — gated on the system_ordering feature (Restaurant
        // Pro). WhatsApp-only plans hand orders off to WhatsApp and have no
        // durable order queue to manage. Deliberately NOT behind
        // subscription.writable: a restaurant whose subscription just expired
        // must still be able to process the orders that already came in.
        Route::middleware('feature:system_ordering')->group(function () {
            Route::get('orders', [DashboardOrderController::class, 'index']);
            Route::get('orders/new-count', [DashboardOrderController::class, 'newCount']);
            Route::patch('orders/{order}/status', [DashboardOrderController::class, 'updateStatus']);
        });

        // Writes (subscription-gated)
        Route::middleware('subscription.writable')->group(function () {
            Route::put('restaurant', [RestaurantProfileController::class, 'update']);

            // Adding branches is a plan capability (multi_branch): single-branch
            // plans can still edit/toggle/delete their existing branch, but only
            // entitled plans may create new ones.
            Route::middleware('feature:multi_branch')->post('branches', [BranchController::class, 'store']);
            Route::put('branches/{branch}', [BranchController::class, 'update']);
            Route::patch('branches/{branch}/status', [BranchController::class, 'toggleOpen']);
            Route::delete('branches/{branch}', [BranchController::class, 'destroy']);

            Route::post('combos', [ComboController::class, 'store']);
            Route::put('combos/{combo}', [ComboController::class, 'update']);
            Route::patch('combos/{combo}/status', [ComboController::class, 'toggleStatus']);
            Route::delete('combos/{combo}', [ComboController::class, 'destroy']);

            Route::post('categories', [CategoryController::class, 'store']);
            Route::patch('categories/reorder', [CategoryController::class, 'reorder']);
            Route::delete('categories/bulk', [CategoryController::class, 'bulkDestroy']);
            Route::put('categories/{category}', [CategoryController::class, 'update']);
            Route::patch('categories/{category}/status', [CategoryController::class, 'toggleStatus']);
            Route::delete('categories/{category}', [CategoryController::class, 'destroy']);

            Route::post('items/import', [MenuImportController::class, 'import']);
            Route::post('items', [MenuItemController::class, 'store']);
            Route::patch('items/reorder', [MenuItemController::class, 'reorder']);
            Route::delete('items/bulk', [MenuItemController::class, 'bulkDestroy']);
            Route::put('items/{item}', [MenuItemController::class, 'update']);
            Route::patch('items/{item}/availability', [MenuItemController::class, 'toggleAvailability']);
            Route::delete('items/{item}', [MenuItemController::class, 'destroy']);
        });

        // Table experience (Phase 1) — gated on the table_management feature.
        Route::middleware('feature:table_management')->group(function () {
            Route::get('dining-areas', [DiningAreaController::class, 'index']);
            Route::get('tables', [TableController::class, 'index']);
            // Live floor grid: occupancy + active-order + open-request signals per table.
            Route::get('tables/live', [TableController::class, 'live']);
            Route::get('tables/{table}/qr', [TableController::class, 'qr']);
            Route::get('tables/{table}/qr/download', [TableController::class, 'qrDownload']);

            Route::middleware('subscription.writable')->group(function () {
                Route::post('dining-areas', [DiningAreaController::class, 'store']);
                Route::put('dining-areas/{area}', [DiningAreaController::class, 'update']);
                Route::patch('dining-areas/{area}/status', [DiningAreaController::class, 'toggleStatus']);
                Route::delete('dining-areas/{area}', [DiningAreaController::class, 'destroy']);

                Route::post('tables', [TableController::class, 'store']);
                Route::post('tables/bulk', [TableController::class, 'bulkStore']);
                Route::put('tables/{table}', [TableController::class, 'update']);
                Route::patch('tables/{table}/status', [TableController::class, 'toggleStatus']);
                Route::post('tables/{table}/qr/regenerate', [TableController::class, 'regenerateQr']);
                Route::delete('tables/bulk', [TableController::class, 'bulkDestroy']);
                Route::delete('tables/{table}', [TableController::class, 'destroy']);
            });
        });

        // Bill requests (Phase 2) — gated on the bill_requests feature. Reads stay
        // available even when the subscription lapsed; the status write is gated.
        Route::middleware('feature:bill_requests')->group(function () {
            Route::get('bill-requests', [BillRequestController::class, 'index']);
            Route::get('bill-requests/new-count', [BillRequestController::class, 'newCount']);

            Route::middleware('subscription.writable')->group(function () {
                Route::patch('bill-requests/{bill}/status', [BillRequestController::class, 'updateStatus']);
            });
        });

        // Internal customer reviews (Phase 3) — gated on the internal_reviews
        // feature. Reads stay available when the subscription lapsed; writes
        // (status + notes) are subscription-gated.
        Route::middleware('feature:internal_reviews')->group(function () {
            Route::get('reviews', [ReviewController::class, 'index']);
            Route::get('reviews/summary', [ReviewController::class, 'summary']);
            Route::get('reviews/{review}', [ReviewController::class, 'show']);

            Route::middleware('subscription.writable')->group(function () {
                Route::patch('reviews/{review}/status', [ReviewController::class, 'updateStatus']);
                Route::post('reviews/{review}/notes', [ReviewController::class, 'addNote']);
            });
        });

        // Product analytics / reports (Phase 4) — gated on the product_analytics
        // feature. All reads; the export streams a CSV/XLSX file.
        Route::middleware('feature:product_analytics')->group(function () {
            Route::get('reports/products-by-time', [ReportController::class, 'productsByTime']);
            Route::get('reports/products-by-time/export', [ReportController::class, 'export']);
            Route::get('reports/dining-areas', [ReportController::class, 'diningAreas']);
        });
    });

/*
|--------------------------------------------------------------------------
| Uploads  (any authenticated admin)
|--------------------------------------------------------------------------
*/
Route::post('uploads/image', [UploadController::class, 'store'])
    ->middleware(['auth:jwt', 'throttle:60,1']);

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

// Table QR scan → context + menu session (Phase 1).
Route::get('public/tables/{token}', [PublicTableController::class, 'show'])
    ->middleware('throttle:120,1');
Route::post('public/tables/{token}/sessions', [PublicTableController::class, 'createSession'])
    ->middleware('throttle:30,1');

// Bill requests raised from a table session (Phase 2).
Route::post('public/sessions/{sessionToken}/bill-requests', [PublicBillRequestController::class, 'store'])
    ->middleware('throttle:20,1');
Route::get('public/bill-requests/{token}', [PublicBillRequestController::class, 'show'])
    ->middleware('throttle:60,1');
Route::patch('public/bill-requests/{token}/cancel', [PublicBillRequestController::class, 'cancel'])
    ->middleware('throttle:20,1');

// Private customer reviews left from the menu (Phase 3).
Route::post('public/restaurants/{slug}/reviews', [PublicReviewController::class, 'store'])
    ->middleware('throttle:10,1');

Route::get('public/restaurants/{slug}/qr', [PublicRestaurantQrController::class, 'show'])
    ->middleware('throttle:120,1');
