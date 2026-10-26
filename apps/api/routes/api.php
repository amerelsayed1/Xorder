<?php

use App\Enums\RoleEnum;
use App\Http\Controllers\Admin\AuditLogController as AdminAuditLogController;
use App\Http\Controllers\Admin\InsightsController as AdminInsightsController;
use App\Http\Controllers\Admin\LandingContentController as AdminLandingContentController;
use App\Http\Controllers\Admin\LeadController as AdminLeadController;
use App\Http\Controllers\Admin\LicenceController as AdminLicenceController;
use App\Http\Controllers\Admin\PlanController as AdminPlanController;
use App\Http\Controllers\Admin\PlatformUserController as AdminPlatformUserController;
use App\Http\Controllers\Admin\PosFleetController as AdminPosFleetController;
use App\Http\Controllers\Admin\RestaurantAdminController as AdminRestaurantAdminController;
use App\Http\Controllers\Admin\RestaurantController as AdminRestaurantController;
use App\Http\Controllers\Admin\RestaurantQrController as AdminQrController;
use App\Http\Controllers\Admin\RestaurantStatusController;
use App\Http\Controllers\Admin\RestaurantTerminalController as AdminRestaurantTerminalController;
use App\Http\Controllers\Admin\SubscriptionController;
use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\Auth\PasswordResetController;
use App\Http\Controllers\Dashboard\BillRequestController;
use App\Http\Controllers\Dashboard\BranchController;
use App\Http\Controllers\Dashboard\CategoryController;
use App\Http\Controllers\Dashboard\ChargeController;
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
use App\Http\Controllers\Dashboard\OptionGroupController;
use App\Http\Controllers\Dashboard\OrderController as DashboardOrderController;
use App\Http\Controllers\Dashboard\PosPinController;
use App\Http\Controllers\Dashboard\PosTerminalController as DashboardPosTerminalController;
use App\Http\Controllers\Dashboard\PulseController;
use App\Http\Controllers\Dashboard\PurchaseOrderController;
use App\Http\Controllers\Dashboard\PurchasingLookupController;
use App\Http\Controllers\Dashboard\PushTokenController;
use App\Http\Controllers\Dashboard\ReceiptProfileController;
use App\Http\Controllers\Dashboard\ReportController;
use App\Http\Controllers\Dashboard\RestaurantProfileController;
use App\Http\Controllers\Dashboard\ReviewController;
use App\Http\Controllers\Dashboard\RoleController;
use App\Http\Controllers\Dashboard\StaffController;
use App\Http\Controllers\Dashboard\StatsController;
use App\Http\Controllers\Dashboard\StockAdjustmentController;
use App\Http\Controllers\Dashboard\StockItemController;
use App\Http\Controllers\Dashboard\StockLevelController;
use App\Http\Controllers\Dashboard\SupplierAccountController;
use App\Http\Controllers\Dashboard\SupplierController;
use App\Http\Controllers\Dashboard\SupplierInvoiceController;
use App\Http\Controllers\Dashboard\SupplierPaymentController;
use App\Http\Controllers\Dashboard\TableController;
use App\Http\Controllers\Dashboard\TaxRuleController;
use App\Http\Controllers\Dashboard\FinancialAccountController;
use App\Http\Controllers\Dashboard\TenderAccountDefaultController;
use App\Http\Controllers\Dashboard\TenderTypeController;
use App\Http\Controllers\Dashboard\UnitController;
use App\Http\Controllers\Pos\BootstrapController as PosBootstrapController;
use App\Http\Controllers\Pos\CustomerController as PosCustomerController;
use App\Http\Controllers\Pos\LicenceController as PosLicenceController;
use App\Http\Controllers\Pos\OrderController as PosOrderController;
use App\Http\Controllers\Pos\RefundController as PosRefundController;
use App\Http\Controllers\Pos\ShiftController as PosShiftController;
use App\Http\Controllers\Pos\TerminalController as PosTerminalController;
use App\Http\Controllers\Public\LandingContentController as PublicLandingContentController;
use App\Http\Controllers\Public\LeadController as PublicLeadController;
use App\Http\Controllers\Public\PublicBillRequestController;
use App\Http\Controllers\Public\PublicCustomerController;
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
        // Self-service password change for any signed-in user (dashboard profile).
        Route::post('change-password', [AuthController::class, 'changePassword'])
            ->middleware('throttle:6,1');
    });
});

/*
|--------------------------------------------------------------------------
| Super Admin panel  (requires an active platform role)
|--------------------------------------------------------------------------
| The outer gate admits any platform staff role; each section is then gated by
| a fine-grained `can:<capability>` ability (see App\Enums\Capability and
| RoleEnum::capabilities()). SUPER_ADMIN bypasses every ability via Gate::before.
*/
Route::prefix('admin')
    ->middleware(['auth:jwt', 'role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT'])
    ->group(function () {
        Route::middleware('can:insights.view')->group(function () {
            Route::get('insights', [AdminInsightsController::class, 'index']);
        });

        // Restaurants — reads vs writes split by capability.
        Route::middleware('can:restaurants.view')->group(function () {
            Route::get('restaurants', [AdminRestaurantController::class, 'index']);
            Route::get('restaurants/stats', [AdminRestaurantController::class, 'stats']);
            Route::get('restaurants/{restaurant}', [AdminRestaurantController::class, 'show']);
            Route::get('restaurants/{restaurant}/qr', [AdminQrController::class, 'show']);
            Route::get('restaurants/{restaurant}/qr/download', [AdminQrController::class, 'download']);
            // Every table of one restaurant as JSON (data + inline QR PNGs).
            Route::get('restaurants/{restaurant}/tables/export', [AdminQrController::class, 'tablesExport']);
        });
        Route::middleware('can:restaurants.manage')->group(function () {
            Route::post('restaurants', [AdminRestaurantController::class, 'store']);
            Route::put('restaurants/{restaurant}', [AdminRestaurantController::class, 'update']);
            Route::delete('restaurants/{restaurant}', [AdminRestaurantController::class, 'destroy']);
            Route::patch('restaurants/{restaurant}/status', [RestaurantStatusController::class, 'update']);
            Route::patch('restaurants/{restaurant}/admin', [AdminRestaurantAdminController::class, 'update']);
            Route::post('restaurants/{restaurant}/admin/reset-password', [AdminRestaurantAdminController::class, 'resetPassword'])
                ->middleware('throttle:10,1');
        });
        Route::middleware('can:subscriptions.manage')->group(function () {
            Route::patch('restaurants/{restaurant}/subscription', [SubscriptionController::class, 'update']);
        });

        // Platform staff users + role assignment (SUPER_ADMIN only).
        Route::middleware('can:platform_users.manage')->group(function () {
            Route::get('users', [AdminPlatformUserController::class, 'index']);
            Route::post('users', [AdminPlatformUserController::class, 'store']);
            Route::get('users/{user}', [AdminPlatformUserController::class, 'show']);
            Route::put('users/{user}', [AdminPlatformUserController::class, 'update']);
            Route::delete('users/{user}', [AdminPlatformUserController::class, 'destroy']);
            Route::post('users/{user}/reset-password', [AdminPlatformUserController::class, 'resetPassword'])
                ->middleware('throttle:10,1');
        });

        // Subscription plans catalog
        Route::middleware('can:plans.manage')->group(function () {
            Route::get('plans', [AdminPlanController::class, 'index']);
            Route::post('plans', [AdminPlanController::class, 'store']);
            Route::get('plans/{plan}', [AdminPlanController::class, 'show']);
            Route::put('plans/{plan}', [AdminPlanController::class, 'update']);
            Route::delete('plans/{plan}', [AdminPlanController::class, 'destroy']);
        });

        // POS licences (POS-BE-015). A licence is its own per-client record,
        // not a projection of the plan — owner decision D6.
        //
        // These reads are deliberately CROSS-TENANT: PosLicence carries no
        // RestaurantScope because licences are administered from the platform
        // side, the same posture POS-BE-022's fleet views need. Every query in
        // the controller names its restaurant explicitly.
        //
        // licences.manage is held by SUPER_ADMIN only (via the Gate::before
        // bypass) and appears in no staff role's matrix: issuing commercial
        // entitlement is not reversible, and widening it later is cheap.
        Route::prefix('pos')->middleware('can:licences.manage')->group(function () {
            Route::get('licences', [AdminLicenceController::class, 'index']);
            Route::post('licences', [AdminLicenceController::class, 'store']);
            // The on-premises customer: a licence with no tenant behind it.
            // Declared before licences/{licence} would ever be consulted, so
            // "offline" is never read as a licence id.
            Route::post('licences/offline', [AdminLicenceController::class, 'storeOffline']);
            Route::get('licences/{licence}', [AdminLicenceController::class, 'show']);
            // The activation key, again — kept encrypted since 16 Oct 2026 and
            // audited on every read. 404 for a licence issued before that.
            Route::get('licences/{licence}/key', [AdminLicenceController::class, 'key']);
            // Renew and revoke are POSTs, not a PUT: neither edits the licence
            // in place. A renewal writes a NEW row and supersedes this one,
            // because the signed artifact is the record of what the customer
            // was sold and overwriting it erases that.
            Route::post('licences/{licence}/renew', [AdminLicenceController::class, 'renew']);
            // Cleanup only: refuses any licence still permitting trade
            // (revoke first). Owner decision 2026-09-05.
            Route::delete('licences/{licence}', [AdminLicenceController::class, 'destroy']);
            Route::post('licences/{licence}/revoke', [AdminLicenceController::class, 'revoke']);
            // R2: the operator's status for the online path. POSTs for the
            // same reason renew and revoke are — each is an act, not an edit.
            Route::post('licences/{licence}/suspend', [AdminLicenceController::class, 'suspend']);
            Route::post('licences/{licence}/resume', [AdminLicenceController::class, 'resume']);
            Route::post('licences/{licence}/expire', [AdminLicenceController::class, 'expire']);
            Route::get('licences/{licence}/terminals', [AdminLicenceController::class, 'terminals']);
            Route::get('licences/{licence}/activations', [AdminLicenceController::class, 'activations']);
            Route::delete('licences/{licence}/activations/{activation}', [AdminLicenceController::class, 'releaseDevice']);
            // The on-premises delivery path: a till that may never reach the
            // internet still has to be licensable.
            Route::get('licences/{licence}/download', [AdminLicenceController::class, 'download']);
        });

        // POS fleet (POS-BE-022). DELIBERATELY CROSS-TENANT — a platform view
        // of every terminal, with heartbeat state; the one POS read that must
        // escape RestaurantScope (no tenant context here, so the scope is a
        // no-op and the controller says so out loud). pos_fleet.view is
        // SUPER_ADMIN-only via Gate::before, like licences.manage.
        Route::prefix('pos')->middleware('can:pos_fleet.view')->group(function () {
            Route::get('terminals', [AdminPosFleetController::class, 'index']);
            Route::get('terminals/{terminal}', [AdminPosFleetController::class, 'show']);
        });

        // Terminals of ONE tenant (owner decision, 2026-09-05). Creating a
        // tenant creates the tenant and its licence and stops there — no
        // terminal, not even a default one — so these are the routes that
        // bring a till into existence, each call one deliberate act.
        //
        // The tenant is a path segment, matching restaurants/{restaurant}/admin
        // and .../subscription: the operator is already on one tenant's page.
        // Reads sit on pos_fleet.view; writes need pos_fleet.manage.
        Route::middleware('can:pos_fleet.view')->group(function () {
            Route::get('restaurants/{restaurant}/terminals', [AdminRestaurantTerminalController::class, 'index']);
        });
        Route::middleware('can:pos_fleet.manage')->group(function () {
            Route::post('restaurants/{restaurant}/terminals', [AdminRestaurantTerminalController::class, 'store']);
            // Plaintext code in this response only; the row keeps the HMAC.
            Route::post('restaurants/{restaurant}/terminals/{terminal}/pairing-code', [AdminRestaurantTerminalController::class, 'pairingCode']);
            Route::post('restaurants/{restaurant}/terminals/{terminal}/revoke', [AdminRestaurantTerminalController::class, 'revoke']);
            // Cleanup only: refuses a terminal still active (revoke first) or
            // holding sales/shift history. Same split as licences.
            Route::delete('restaurants/{restaurant}/terminals/{terminal}', [AdminRestaurantTerminalController::class, 'destroy']);
        });

        // Landing page content (CMS)
        Route::middleware('can:landing.manage')->group(function () {
            Route::get('landing-content', [AdminLandingContentController::class, 'show']);
            Route::put('landing-content', [AdminLandingContentController::class, 'update']);
        });

        // Landing page leads (sales inbox)
        Route::middleware('can:leads.manage')->group(function () {
            Route::get('leads', [AdminLeadController::class, 'index']);
            Route::get('leads/export', [AdminLeadController::class, 'export']);
            Route::patch('leads/{lead}', [AdminLeadController::class, 'update']);
        });

        // Audit trail — read-only activity log across all tenants.
        Route::middleware('can:audit.view')->group(function () {
            Route::get('audit-logs', [AdminAuditLogController::class, 'index']);
            Route::get('audit-logs/filters', [AdminAuditLogController::class, 'filters']);
            // The trail is stored as one file per day; these expose that directly.
            Route::get('audit-logs/files', [AdminAuditLogController::class, 'files']);
            Route::get('audit-logs/files/{date}', [AdminAuditLogController::class, 'download'])
                ->where('date', '\d{4}-\d{2}-\d{2}');
        });
    });

/*
|--------------------------------------------------------------------------
| Restaurant Dashboard  (requires an active tenant role)
|--------------------------------------------------------------------------
| The outer gate admits the restaurant owner (RESTAURANT_ADMIN) and its staff
| accounts (RESTAURANT_STAFF); each section is then gated by a fine-grained
| `can:<tenant capability>` ability (see App\Enums\TenantCapability). The owner
| holds every one of them implicitly; staff hold exactly what the Role assigned
| to them lists.
|
| Three orthogonal gates stack here, and they answer different questions:
|   role:…                 which portal this account belongs to
|   feature:<key>          whether the *tenant* bought this capability (plan)
|   can:<tenant capability> whether this *person* may do it
|   subscription.writable  whether the tenant may write at all right now
*/
Route::prefix('dashboard')
    ->middleware(['auth:jwt', 'role:'.implode(',', RoleEnum::tenantRoles())])
    ->group(function () {
        // Shell endpoints — open to every tenant account regardless of role.
        // Push-notification device tokens (not subscription-gated).
        Route::post('push/token', [PushTokenController::class, 'store']);
        Route::delete('push/token', [PushTokenController::class, 'destroy']);

        // Consolidated dashboard heartbeat: new-order + bill-request + unread
        // notification counts in one ETag'd request, so the shell polls once
        // instead of three times. Counts respect each feature gate internally,
        // and are zeroed for a user without the matching capability.
        Route::get('pulse', [PulseController::class, 'index']);

        // In-app notification centre. Not subscription- or feature-gated: every
        // admin keeps their inbox even on a lapsed plan, and notifications span
        // multiple features (orders, bill requests, reviews, subscription).
        Route::get('notifications', [NotificationController::class, 'index']);
        Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
        Route::post('notifications/read-all', [NotificationController::class, 'markAllRead']);
        Route::patch('notifications/{notification}/read', [NotificationController::class, 'markRead']);

        // Turn a pasted Google Maps link (or share short link) into lat/lng for
        // the profile and branch forms. A stateless helper — neither capability-
        // nor subscription-gated, since it writes nothing and touches no tenant
        // data; the resolved coordinates are saved through a gated endpoint.
        Route::post('geo/resolve-map-link', [MapLinkController::class, 'resolve']);

        /*
        | Staff accounts & custom roles.
        */
        Route::middleware('can:staff.view')->group(function () {
            Route::get('roles', [RoleController::class, 'index']);
            Route::get('roles/capabilities', [RoleController::class, 'capabilities']);
            Route::get('roles/{role}', [RoleController::class, 'show']);
            Route::get('staff', [StaffController::class, 'index']);
            Route::get('staff/{staff}', [StaffController::class, 'show']);

            Route::middleware('subscription.writable')->group(function () {
                // Roles follow the staff verbs: defining who may do what is the
                // same privilege as deciding who works here.
                Route::middleware('can:staff.create')->post('roles', [RoleController::class, 'store']);
                Route::middleware('can:staff.update')->put('roles/{role}', [RoleController::class, 'update']);
                Route::middleware('can:staff.delete')->delete('roles/{role}', [RoleController::class, 'destroy']);

                Route::middleware('can:staff.create')->post('staff', [StaffController::class, 'store']);
                Route::middleware('can:staff.update')->put('staff/{staff}', [StaffController::class, 'update']);
                Route::middleware('can:staff.delete')->delete('staff/{staff}', [StaffController::class, 'destroy']);
                // Resetting a password is editing the account, not creating one.
                Route::middleware('can:staff.update')
                    ->post('staff/{staff}/reset-password', [StaffController::class, 'resetPassword'])
                    ->middleware('throttle:10,1');
            });
        });

        /*
        | Restaurant profile, branding and the restaurant-level QR code.
        */
        Route::middleware('can:settings.view')->group(function () {
            Route::get('restaurant', [RestaurantProfileController::class, 'show']);
            Route::get('qr', [DashboardQrController::class, 'show']);
            Route::get('qr/download', [DashboardQrController::class, 'download']);

            Route::middleware(['can:settings.update', 'subscription.writable'])
                ->put('restaurant', [RestaurantProfileController::class, 'update']);
        });

        /*
        | Dashboard stats & insights.
        */
        Route::middleware('can:analytics.view')->group(function () {
            Route::get('stats', [StatsController::class, 'index']);
            Route::get('insights', [DashboardInsightsController::class, 'index']);
        });

        /*
        | Branches.
        */
        // Reading the list is reference data for any branch-scoped screen (see
        // the branches.list gate); the presence probe stays on branches.view.
        Route::middleware('can:branches.list')->get('branches', [BranchController::class, 'index']);
        Route::middleware('can:branches.view')->group(function () {
            // Observational only — reports whether diners arrive on this branch's
            // own customer Wi-Fi; nothing here changes how sessions are admitted.
            Route::get('branches/{branch}/presence', [BranchController::class, 'presence']);
        });
        Route::middleware('subscription.writable')->group(function () {
            // Adding branches is a plan capability (multi_branch): single-branch
            // plans can still edit/toggle/delete their existing branch, but only
            // entitled plans may create new ones.
            Route::middleware(['can:branches.create', 'feature:multi_branch'])
                ->post('branches', [BranchController::class, 'store']);

            Route::middleware('can:branches.update')->group(function () {
                Route::put('branches/{branch}', [BranchController::class, 'update']);
                // Declare the branch's customer Wi-Fi address by hand — the setup
                // path before enough verified scans exist to learn it.
                Route::put('branches/{branch}/presence/egress-ips', [BranchController::class, 'updateEgressIps']);
                Route::patch('branches/{branch}/status', [BranchController::class, 'toggleOpen']);
            });

            Route::middleware('can:branches.delete')->delete('branches/{branch}', [BranchController::class, 'destroy']);
        });

        /*
        | Menu — items, categories, combos and the shared "extras" library.
        */
        Route::middleware('can:menu.view')->group(function () {
            Route::get('combos', [ComboController::class, 'index']);
            Route::get('categories', [CategoryController::class, 'index']);
            Route::get('categories/{category}', [CategoryController::class, 'show']);
            Route::get('items', [MenuItemController::class, 'index']);
            Route::get('option-groups', [OptionGroupController::class, 'index']);
            Route::get('option-groups/{optionGroup}', [OptionGroupController::class, 'show']);
            // Export the menu to CSV/XLSX. A read — deliberately NOT behind
            // subscription.writable, so a read-only tenant can still get their data
            // out. Registered before items/{item} so "export" isn't matched as an id.
            Route::get('items/export', [MenuExportController::class, 'export']);
            Route::get('items/{item}', [MenuItemController::class, 'show']);
        });
        Route::middleware('subscription.writable')->group(function () {
            Route::middleware('can:menu.create')->group(function () {
                Route::post('combos', [ComboController::class, 'store']);
                Route::post('categories', [CategoryController::class, 'store']);
                Route::post('categories/bulk', [CategoryController::class, 'bulkStore']);
                Route::post('option-groups', [OptionGroupController::class, 'store']);
                Route::post('items', [MenuItemController::class, 'store']);
                // An import adds rows (and updates matched ones), so it needs
                // both verbs rather than counting as a plain create.
                Route::middleware('can:menu.update')->post('items/import', [MenuImportController::class, 'import']);
            });

            // Reordering, renaming and toggling availability are all edits.
            Route::middleware('can:menu.update')->group(function () {
                Route::put('combos/{combo}', [ComboController::class, 'update']);
                Route::patch('combos/{combo}/status', [ComboController::class, 'toggleStatus']);

                Route::patch('categories/reorder', [CategoryController::class, 'reorder']);
                Route::put('categories/{category}', [CategoryController::class, 'update']);
                Route::patch('categories/{category}/status', [CategoryController::class, 'toggleStatus']);

                Route::put('option-groups/{optionGroup}', [OptionGroupController::class, 'update']);

                Route::patch('items/reorder', [MenuItemController::class, 'reorder']);
                Route::put('items/{item}', [MenuItemController::class, 'update']);
                Route::patch('items/{item}/availability', [MenuItemController::class, 'toggleAvailability']);
            });

            Route::middleware('can:menu.delete')->group(function () {
                Route::delete('combos/{combo}', [ComboController::class, 'destroy']);
                Route::delete('categories/bulk', [CategoryController::class, 'bulkDestroy']);
                Route::delete('categories/{category}', [CategoryController::class, 'destroy']);
                Route::delete('option-groups/{optionGroup}', [OptionGroupController::class, 'destroy']);
                Route::delete('items/bulk', [MenuItemController::class, 'bulkDestroy']);
                Route::delete('items/{item}', [MenuItemController::class, 'destroy']);
            });
        });

        /*
        | Customer directory — available on every plan. Customers are captured
        | for all ordering types (system orders and WhatsApp checkout alike), so
        | the restaurant always keeps its customer list.
        */
        Route::middleware('can:customers.view')->group(function () {
            Route::get('customers', [CustomerController::class, 'index']);
            Route::get('customers/{customer}', [CustomerController::class, 'show']);
        });

        /*
        | Order management — open to a restaurant holding EITHER system_ordering
        | (Restaurant Pro: online orders land here) OR pos (a till's sales land
        | here too, as channel=pos rows). WhatsApp-only plans hand orders off
        | to WhatsApp and have no durable order queue to manage; a plan with the
        | POS paid for the till and must see what it rang up (S2-1, 16 Oct
        | 2026). Deliberately NOT behind subscription.writable: a restaurant
        | whose subscription just expired must still be able to process the
        | orders that already came in.
        */
        Route::middleware('feature:system_ordering|pos')->group(function () {
            // orders.read = orders.view OR live.view (see AppServiceProvider).
            Route::middleware('can:orders.read')->group(function () {
                Route::get('orders', [DashboardOrderController::class, 'index']);
                Route::get('orders/new-count', [DashboardOrderController::class, 'newCount']);
            });
            Route::middleware('can:orders.update')
                ->patch('orders/{order}/status', [DashboardOrderController::class, 'updateStatus']);
        });

        /*
        | Table experience (Phase 1) — gated on the table_management feature.
        */
        Route::middleware('feature:table_management')->group(function () {
            // Live floor grid: occupancy + active-order + open-request signals
            // per table. Sits OUTSIDE the tables.view group on purpose — nested
            // it would inherit that gate and live.view could never reach it.
            Route::middleware('can:tables.live')->get('tables/live', [TableController::class, 'live']);

            Route::middleware('can:tables.view')->group(function () {
                Route::get('dining-areas', [DiningAreaController::class, 'index']);
                Route::get('tables', [TableController::class, 'index']);
                Route::get('tables/{table}/qr', [TableController::class, 'qr']);
                Route::get('tables/{table}/qr/download', [TableController::class, 'qrDownload']);
                // Bundle several tables' QR PNGs into one ZIP (read-only, no writable gate).
                Route::post('tables/qr/download-bulk', [TableController::class, 'qrDownloadBulk']);
            });

            // Closing out a visit is floor work, not configuration — it stays
            // available on a lapsed subscription like order handling does, and
            // counts as an edit rather than a deletion.
            Route::middleware('can:tables.update')
                ->post('tables/{table}/visit/finish', [TableController::class, 'finishVisit']);

            Route::middleware('subscription.writable')->group(function () {
                Route::middleware('can:tables.create')->group(function () {
                    Route::post('dining-areas', [DiningAreaController::class, 'store']);
                    Route::post('tables', [TableController::class, 'store']);
                    Route::post('tables/bulk', [TableController::class, 'bulkStore']);
                });

                Route::middleware('can:tables.update')->group(function () {
                    Route::put('dining-areas/{area}', [DiningAreaController::class, 'update']);
                    Route::patch('dining-areas/{area}/status', [DiningAreaController::class, 'toggleStatus']);
                    Route::put('tables/{table}', [TableController::class, 'update']);
                    Route::patch('tables/{table}/status', [TableController::class, 'toggleStatus']);
                    // Rotating a QR invalidates the printed one — an edit to the
                    // table, not a new table.
                    Route::post('tables/{table}/qr/regenerate', [TableController::class, 'regenerateQr']);
                });

                Route::middleware('can:tables.delete')->group(function () {
                    Route::delete('dining-areas/{area}', [DiningAreaController::class, 'destroy']);
                    Route::delete('tables/bulk', [TableController::class, 'bulkDestroy']);
                    Route::delete('tables/{table}', [TableController::class, 'destroy']);
                });
            });
        });

        /*
        | Bill requests (Phase 2) — gated on the bill_requests feature. Reads stay
        | available even when the subscription lapsed; the status write is gated.
        */
        Route::middleware('feature:bill_requests')->group(function () {
            // bills.read = bills.view OR live.view.
            Route::middleware('can:bills.read')->group(function () {
                Route::get('bill-requests', [BillRequestController::class, 'index']);
                Route::get('bill-requests/new-count', [BillRequestController::class, 'newCount']);
            });

            Route::middleware(['can:bills.update', 'subscription.writable'])
                ->patch('bill-requests/{bill}/status', [BillRequestController::class, 'updateStatus']);
        });

        /*
        | Internal customer reviews (Phase 3) — gated on the internal_reviews
        | feature. Reads stay available when the subscription lapsed; writes
        | (status + notes) are subscription-gated.
        */
        Route::middleware('feature:internal_reviews')->group(function () {
            Route::middleware('can:reviews.view')->group(function () {
                Route::get('reviews', [ReviewController::class, 'index']);
                Route::get('reviews/summary', [ReviewController::class, 'summary']);
                Route::get('reviews/{review}', [ReviewController::class, 'show']);
            });

            Route::middleware(['can:reviews.update', 'subscription.writable'])->group(function () {
                Route::patch('reviews/{review}/status', [ReviewController::class, 'updateStatus']);
                Route::post('reviews/{review}/notes', [ReviewController::class, 'addNote']);
            });
        });

        /*
        | Product analytics / reports (Phase 4) — gated on the product_analytics
        | feature. All reads; the export streams a CSV/XLSX file.
        */
        Route::middleware(['feature:product_analytics', 'can:reports.view'])->group(function () {
            Route::get('reports/products-by-time', [ReportController::class, 'productsByTime']);
            Route::get('reports/products-by-time/export', [ReportController::class, 'export']);
            Route::get('reports/dining-areas', [ReportController::class, 'diningAreas']);
        });

        /*
        | Purchasing and inventory (CB-09). A STANDALONE feature: it is
        | deliberately NOT nested under feature:pos, because a café or a cloud
        | kitchen with no till may buy it (owner decision 2026-09-12).
        |
        |   feature:purchasing    the tenant bought purchasing
        |   can:purchase.manage   ONE capability for reads AND writes: who a
        |                         business buys from is its commercial
        |                         position, so reading is gated too (till
        |                         doc 16 §6). There is no purchase.view.
        |   subscription.writable on writes, like every configuration write
        |
        | No DELETE on any purchasing resource. Suppliers, units and stock
        | items are retired with is_active=false, because later purchasing rows
        | keep pointing at them; an unwanted purchase order is cancelled; stock
        | movements are append-only.
        |
        | Slice b: stock items, purchase orders, receiving, stock levels.
        | Every PO transition (edit, send, cancel, receive, close short) is a
        | service call that locks the order row and re-reads its status under
        | the lock, so the route decides only WHO may try, never whether the
        | order allows it.
        |
        | Slice c: supplier invoices, supplier payments and their allocations,
        | and supplier balances (derived on every read, never stored). An
        | invoice's live allocations never exceed its total: enforced by
        | SupplierLedgerService under a lock on the invoice row, not here.
        |
        | Slice d (D12, owner 2026-09-13): opening stock, waste, adjustments
        | and counts. Create only: each is one new movement in the same
        | append-only ledger, written by StockAdjustmentService under the
        | level-row lock receiving takes. It never touches a purchase order.
        */
        Route::middleware(['feature:purchasing', 'can:purchase.manage'])->group(function () {
            Route::get('units', [UnitController::class, 'index']);
            Route::get('units/{unit}', [UnitController::class, 'show']);
            Route::get('suppliers', [SupplierController::class, 'index']);
            // Before suppliers/{supplier}, or the binding would swallow "balances".
            Route::get('suppliers/balances', [SupplierAccountController::class, 'balances']);
            Route::get('suppliers/{supplier}', [SupplierController::class, 'show']);
            Route::get('suppliers/{supplier}/account', [SupplierAccountController::class, 'account']);
            Route::get('supplier-invoices', [SupplierInvoiceController::class, 'index']);
            Route::get('supplier-invoices/{supplierInvoice}', [SupplierInvoiceController::class, 'show']);
            Route::get('supplier-payments', [SupplierPaymentController::class, 'index']);
            Route::get('supplier-payments/{supplierPayment}', [SupplierPaymentController::class, 'show']);
            // Till pay-outs not yet linked to a payment (design D13). Read-only.
            Route::get('purchasing/drawer-payouts', [SupplierPaymentController::class, 'drawerPayouts']);
            // Branch/supplier/unit/item/menu-item pickers under purchase.manage
            // alone (ids and names only), so a buyer needs no menu or branch grant.
            Route::get('purchasing/lookups', [PurchasingLookupController::class, 'index']);
            Route::get('stock-items', [StockItemController::class, 'index']);
            Route::get('stock-items/{stockItem}', [StockItemController::class, 'show']);
            Route::get('stock-items/{stockItem}/movements', [StockItemController::class, 'movements']);
            // Recorded stock, not on hand: tills don't deduct sales (D4).
            Route::get('stock-levels', [StockLevelController::class, 'index']);
            Route::get('purchase-orders', [PurchaseOrderController::class, 'index']);
            Route::get('purchase-orders/{purchaseOrder}', [PurchaseOrderController::class, 'show']);

            Route::middleware('subscription.writable')->group(function () {
                Route::post('units', [UnitController::class, 'store']);
                // `code` is immutable: UpdateUnitRequest has no rule for it.
                Route::put('units/{unit}', [UnitController::class, 'update']);
                Route::post('suppliers', [SupplierController::class, 'store']);
                Route::put('suppliers/{supplier}', [SupplierController::class, 'update']);
                Route::delete('suppliers/{supplier}', [SupplierController::class, 'destroy']);
                // The unit can't change while stock is held or the item is on
                // a draft or open order (StockItemService, under a lock).
                Route::post('stock-items', [StockItemController::class, 'store']);
                Route::put('stock-items/{stockItem}', [StockItemController::class, 'update']);
                Route::post('purchase-orders', [PurchaseOrderController::class, 'store']);
                // Draft only; replaces the lines wholesale.
                Route::put('purchase-orders/{purchaseOrder}', [PurchaseOrderController::class, 'update']);
                Route::post('purchase-orders/{purchaseOrder}/send', [PurchaseOrderController::class, 'send']);
                // Draft or sent only; refused once anything has arrived.
                Route::post('purchase-orders/{purchaseOrder}/cancel', [PurchaseOrderController::class, 'cancel']);
                Route::post('purchase-orders/{purchaseOrder}/receipts', [PurchaseOrderController::class, 'receive']);
                // Slice d: {kind: opening|waste|adjustment|count, ...}. A new
                // movement every time; a wrong one is corrected by another.
                Route::post('stock-adjustments', [StockAdjustmentController::class, 'store']);
                // D11 (owner, 2026-09-13): close a part delivery short. Only
                // a partly received order; never touches stock.
                Route::post('purchase-orders/{purchaseOrder}/close', [PurchaseOrderController::class, 'closeShort']);
                // PUT only while live and nothing is allocated; void keeps it on record.
                Route::post('supplier-invoices', [SupplierInvoiceController::class, 'store']);
                Route::put('supplier-invoices/{supplierInvoice}', [SupplierInvoiceController::class, 'update']);
                Route::post('supplier-invoices/{supplierInvoice}/void', [SupplierInvoiceController::class, 'void']);
                // No update: a wrong payment is voided and entered again.
                Route::post('supplier-payments', [SupplierPaymentController::class, 'store']);
                Route::post('supplier-payments/{supplierPayment}/void', [SupplierPaymentController::class, 'void']);
            });
        });

        /*
        | POS (Cloud Wave 1). Everything below is feature:pos — the tenant
        | bought the POS — and then:
        |
        |   terminals    can:pos.provision  (POS-BE-023: provision, pairing
        |                codes, revoke — a dedicated verb, so an installer
        |                account needn't hold settings.update)
        |   money config can:settings.view / settings.update (POS-BE-013 —
        |                authoring what money means is settings work)
        |   PIN          its own controller guard (POS-BE-024): staff.update
        |                for others, self always, owner's pin only by owner
        |
        | Writes stack subscription.writable like every other dashboard
        | CONFIGURATION write. (D2 exempts the TILL's money path, not this.)
        */
        Route::middleware('feature:pos')->group(function () {
            Route::middleware('can:pos.provision')->group(function () {
                Route::get('pos/terminals', [DashboardPosTerminalController::class, 'index']);

                Route::middleware('subscription.writable')->group(function () {
                    Route::post('pos/terminals', [DashboardPosTerminalController::class, 'store']);
                    Route::post('pos/terminals/{terminal}/pairing-code', [DashboardPosTerminalController::class, 'pairingCode'])
                        ->middleware('throttle:10,1');
                    Route::post('pos/terminals/{terminal}/revoke', [DashboardPosTerminalController::class, 'revoke']);
                    // Cleanup only: refuses unless revoked AND never traded
                    // (shifts cascade, orders lose attribution). Owner
                    // decision 2026-09-05, mirroring the licence split.
                    Route::delete('pos/terminals/{terminal}', [DashboardPosTerminalController::class, 'destroy']);
                });
            });

            Route::middleware('can:settings.view')->group(function () {
                // A3 / CB-08 — who the receipt says sold the food, per branch.
                // Same gate pair as the money config, and for the same reason:
                // the legal identity printed on a slip is settings work, it is
                // the same class of fact as the restaurant profile's own tax
                // registration number (which `settings.update` already
                // authors), and a separate capability would leave every role
                // that can edit tax unable to edit the header it prints on.
                // `{branch}` is route model bound, so another tenant's branch
                // is a 404.
                Route::get('receipt-profiles', [ReceiptProfileController::class, 'index']);

                Route::get('tax-rules', [TaxRuleController::class, 'index']);
                Route::get('charges', [ChargeController::class, 'index']);
                Route::get('tender-types', [TenderTypeController::class, 'index']);
                // XORD-015: the money accounts, and which one each payment
                // method pays into. Reading rides on settings.view (the
                // payment-method editor needs the list); every write needs
                // finance.accounts, NOT settings.update, so editing a payment
                // method never lets someone redirect the money. DELETE
                // deactivates — an account is never removed.
                Route::get('financial-accounts', [FinancialAccountController::class, 'index']);
                Route::get('tender-account-defaults', [TenderAccountDefaultController::class, 'index']);

                Route::middleware(['can:finance.accounts', 'subscription.writable'])->group(function () {
                    Route::post('financial-accounts', [FinancialAccountController::class, 'store']);
                    Route::put('financial-accounts/{financialAccount}', [FinancialAccountController::class, 'update']);
                    Route::delete('financial-accounts/{financialAccount}', [FinancialAccountController::class, 'destroy']);
                    Route::put('tender-account-defaults', [TenderAccountDefaultController::class, 'update']);
                });

                Route::middleware(['can:settings.update', 'subscription.writable'])->group(function () {
                    Route::put('receipt-profiles/{branch}', [ReceiptProfileController::class, 'update']);

                    Route::post('tax-rules', [TaxRuleController::class, 'store']);
                    Route::put('tax-rules/{taxRule}', [TaxRuleController::class, 'update']);
                    Route::delete('tax-rules/{taxRule}', [TaxRuleController::class, 'destroy']);
                    Route::post('charges', [ChargeController::class, 'store']);
                    Route::put('charges/{charge}', [ChargeController::class, 'update']);
                    Route::delete('charges/{charge}', [ChargeController::class, 'destroy']);
                    Route::post('tender-types', [TenderTypeController::class, 'store']);
                    Route::put('tender-types/{tenderType}', [TenderTypeController::class, 'update']);
                    // DELETE deactivates — order_payments keep their FK.
                    Route::delete('tender-types/{tenderType}', [TenderTypeController::class, 'destroy']);
                });
            });

            // The PIN is write-only and never readable back; per-target
            // authorization (self / staff.update / owner-only-by-owner) lives
            // in the controller guard, which also 404s cross-tenant targets.
            Route::middleware('subscription.writable')->group(function () {
                Route::put('staff/{staff}/pin', [PosPinController::class, 'update'])->middleware('throttle:10,1');
                Route::delete('staff/{staff}/pin', [PosPinController::class, 'destroy'])->middleware('throttle:10,1');
            });
        });
    });

/*
|--------------------------------------------------------------------------
| POS terminals  (POS-BE-015)
|--------------------------------------------------------------------------
|
| `activate` is UNAUTHENTICATED on purpose: the activation key is itself the
| credential, and requiring a login would defeat the point — an installer
| standing at a till on a fresh machine has a key and nothing else. It is
| throttled per IP and per key (see the `licence-activate` limiter) and every
| attempt, successful or not, is audited with the key TAIL only.
|
| Note what is deliberately NOT here: EnsureSubscriptionAllowsWrites. A lapsed
| subscription must not stop a till installing a licence the customer already
| paid for — that turns a collections problem into an outage, the same
| reasoning as D2.
|
| `current` is now behind the DEVICE credential (the provisional jwt gating
| was tightened when POS-BE-011/023 landed, exactly as the shipped contract
| said it would be). It runs in no-feature mode: reading your licence must
| work even when the feature flag is off — that is how a till learns WHY.
|
*/
Route::post('pos/licence/activate', [PosLicenceController::class, 'activate'])
    ->middleware('throttle:licence-activate');

// The signing key's public half and its id, for a release build of the till
// to be compiled with (audit S1-2). Public by definition; no credential.
Route::get('pos/licence/issuer', [PosLicenceController::class, 'issuer'])
    ->middleware('throttle:60,1');

Route::get('pos/licence/current', [PosLicenceController::class, 'current'])
    ->middleware(['pos.device:no-feature', 'throttle:60,1']);

// The online verdict for a connected till (R2, POS-BE-031) — asked on the
// splash screen and before each shift. Same tier as `current`: device
// credential, no-feature (a lapsed till must hear why), no subscription.writable.
// Spelled `license` as the contract fixed it; the till already calls it so.
Route::post('pos/license/check', [PosLicenceController::class, 'check'])
    ->middleware(['pos.device:no-feature', 'throttle:60,1']);

/*
|--------------------------------------------------------------------------
| POS terminals — Cloud Wave 1 (POS-BE-006/007/008/009/011/019/020/022/023)
|--------------------------------------------------------------------------
|
| Three auth tiers, per the agreed contracts:
|
|   claim       UNAUTHENTICATED — the pairing code is the credential, hashed
|               at rest, single-use, 24h TTL, throttled per IP + per slug.
|   register    staff JWT holding pos.provision (Path B) — the JWT is used for
|               this one call and never stored by the till.
|   everything  the DEVICE token (pos.device middleware): the terminal is
|   else        authenticated, the cashier is identified (acting_user_id,
|               verified locally by PIN). No cashier JWT is ever at the till.
|
| The heartbeat runs in no-feature mode ON PURPOSE: a tenant whose pos flag
| lapsed must keep appearing in the fleet view — POS_FEATURE_DISABLED on the
| heartbeat would silence exactly the tills Super Admin most needs to see.
|
| subscription.writable is ABSENT from all of it (owner decision D2): a lapsed
| plan never stops a till taking or reporting money. SUBSCRIPTION_LAPSED stays
| reserved in the error vocabulary should the owner ever reverse that.
*/
Route::post('pos/terminals/claim', [PosTerminalController::class, 'claim'])
    ->middleware('throttle:pos-claim');

Route::post('pos/terminals/register', [PosTerminalController::class, 'register'])
    ->middleware(['auth:jwt', 'role:'.implode(',', RoleEnum::tenantRoles()), 'feature:pos', 'can:pos.provision', 'throttle:10,1']);

Route::post('pos/terminals/heartbeat', [PosTerminalController::class, 'heartbeat'])
    ->middleware(['pos.device:no-feature', 'throttle:120,1']);

Route::middleware(['pos.device', 'throttle:240,1'])->group(function () {
    Route::get('pos/bootstrap', [PosBootstrapController::class, 'show']);
    Route::post('pos/terminals/rotate-token', [PosTerminalController::class, 'rotateToken']);

    // Order lookup is registered before the {order} payment route so
    // "by-client-id" is never matched as an order reference.
    Route::get('pos/orders/by-client-id/{uuid}', [PosOrderController::class, 'byClientId']);
    Route::post('pos/orders', [PosOrderController::class, 'store']);
    Route::post('pos/orders/{order}/payments', [PosOrderController::class, 'storePayment']);

    // Refunds (POS-BE-010). Same device credential and the same three tiers of
    // gate as an order: the terminal is authenticated, the cashier is named in
    // `acting_user_id` and must hold `pos.refund` (or `pos.void` when the
    // refund is a void), and the money invariants are the server's — a refund
    // can never exceed what was sold. Lookup before the collection route for
    // the same reason the order one is: "by-client-id" must never be eaten as
    // a path parameter.
    Route::get('pos/refunds/by-client-id/{uuid}', [PosRefundController::class, 'byClientId']);
    Route::post('pos/refunds', [PosRefundController::class, 'store']);

    // Customers (POS-BE-014). The same device credential as an order, and the
    // cashier — when the till names one — must hold `customers.create`, the
    // first write verb on the directory. Deliberately NOT gated on
    // `customers.view`: reading the dashboard's directory and adding somebody
    // at the counter are different acts, and a cashier does the second.
    Route::post('pos/customers', [PosCustomerController::class, 'store']);

    Route::get('pos/shifts/current', [PosShiftController::class, 'current']);
    Route::post('pos/shifts', [PosShiftController::class, 'open']);
    Route::post('pos/shifts/{shift}/close', [PosShiftController::class, 'close']);
    Route::get('pos/shifts/{shift}/report', [PosShiftController::class, 'report']);
    Route::post('pos/cash-movements', [PosShiftController::class, 'cashMovement']);
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

// Status-only read of a guest order, so the menu SPA can tell on a diner's
// return whether their order is closed and it's time to ask for feedback.
Route::get('public/restaurants/{slug}/orders/{id}/status', [PublicOrderController::class, 'status'])
    ->middleware('throttle:60,1');

// WhatsApp checkout captures just the customer (no order record) so the
// restaurant still builds its directory. Same throttle as guest orders.
Route::post('public/restaurants/{slug}/customers', [PublicCustomerController::class, 'store'])
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
