# Cloud route index (generated)

Generated 2026-10-20 from `apps/xorder-cloud/apps/api/routes/{api,web}.php` at cloud `main 06bc8e3` by `python3 -I scripts/harness/route-index.py` (static parse; the app is never booted). Regenerate with the same command and diff to find new, removed or re-gated routes; the row count is cross-checked against a direct count of route-verb calls in the source (249 in `api.php`, plus 3 in `web.php`). Middleware lists are the literal strings in the route chain, including inherited group middleware; computed parts such as `'role:'.implode(...)` appear as their literal part.

| Method | Path | Middleware | Controller@method | Source |
| Method | Path | Middleware | Controller@method | Source |
| --- | --- | --- | --- | --- |
| POST | `/api/auth/login` | `throttle:login` | `Auth\AuthController@login` | `api.php:87` |
| POST | `/api/auth/forgot-password` | `throttle:5,1` | `Auth\PasswordResetController@forgot` | `api.php:88` |
| POST | `/api/auth/reset-password` | `throttle:5,1` | `Auth\PasswordResetController@reset` | `api.php:89` |
| POST | `/api/auth/logout` | `auth:jwt` | `Auth\AuthController@logout` | `api.php:92` |
| GET | `/api/auth/me` | `auth:jwt` | `Auth\AuthController@me` | `api.php:93` |
| POST | `/api/auth/change-password` | `auth:jwt`, `throttle:6,1` | `Auth\AuthController@changePassword` | `api.php:95` |
| GET | `/api/admin/insights` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:insights.view` | `Admin\InsightsController@index` | `api.php:112` |
| GET | `/api/admin/restaurants` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantController@index` | `api.php:117` |
| GET | `/api/admin/restaurants/stats` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantController@stats` | `api.php:118` |
| GET | `/api/admin/restaurants/{restaurant}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantController@show` | `api.php:119` |
| GET | `/api/admin/restaurants/{restaurant}/qr` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantQrController@show` | `api.php:120` |
| GET | `/api/admin/restaurants/{restaurant}/qr/download` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantQrController@download` | `api.php:121` |
| GET | `/api/admin/restaurants/{restaurant}/tables/export` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.view` | `Admin\RestaurantQrController@tablesExport` | `api.php:123` |
| POST | `/api/admin/restaurants` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage` | `Admin\RestaurantController@store` | `api.php:126` |
| PUT | `/api/admin/restaurants/{restaurant}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage` | `Admin\RestaurantController@update` | `api.php:127` |
| DELETE | `/api/admin/restaurants/{restaurant}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage` | `Admin\RestaurantController@destroy` | `api.php:128` |
| PATCH | `/api/admin/restaurants/{restaurant}/status` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage` | `Admin\RestaurantStatusController@update` | `api.php:129` |
| PATCH | `/api/admin/restaurants/{restaurant}/admin` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage` | `Admin\RestaurantAdminController@update` | `api.php:130` |
| POST | `/api/admin/restaurants/{restaurant}/admin/reset-password` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:restaurants.manage`, `throttle:10,1` | `Admin\RestaurantAdminController@resetPassword` | `api.php:131` |
| PATCH | `/api/admin/restaurants/{restaurant}/subscription` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:subscriptions.manage` | `Admin\SubscriptionController@update` | `api.php:135` |
| GET | `/api/admin/users` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage` | `Admin\PlatformUserController@index` | `api.php:140` |
| POST | `/api/admin/users` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage` | `Admin\PlatformUserController@store` | `api.php:141` |
| GET | `/api/admin/users/{user}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage` | `Admin\PlatformUserController@show` | `api.php:142` |
| PUT | `/api/admin/users/{user}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage` | `Admin\PlatformUserController@update` | `api.php:143` |
| DELETE | `/api/admin/users/{user}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage` | `Admin\PlatformUserController@destroy` | `api.php:144` |
| POST | `/api/admin/users/{user}/reset-password` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:platform_users.manage`, `throttle:10,1` | `Admin\PlatformUserController@resetPassword` | `api.php:145` |
| GET | `/api/admin/plans` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:plans.manage` | `Admin\PlanController@index` | `api.php:151` |
| POST | `/api/admin/plans` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:plans.manage` | `Admin\PlanController@store` | `api.php:152` |
| GET | `/api/admin/plans/{plan}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:plans.manage` | `Admin\PlanController@show` | `api.php:153` |
| PUT | `/api/admin/plans/{plan}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:plans.manage` | `Admin\PlanController@update` | `api.php:154` |
| DELETE | `/api/admin/plans/{plan}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:plans.manage` | `Admin\PlanController@destroy` | `api.php:155` |
| GET | `/api/admin/pos/licences` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@index` | `api.php:170` |
| POST | `/api/admin/pos/licences` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@store` | `api.php:171` |
| POST | `/api/admin/pos/licences/offline` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@storeOffline` | `api.php:175` |
| GET | `/api/admin/pos/licences/{licence}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@show` | `api.php:176` |
| GET | `/api/admin/pos/licences/{licence}/key` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@key` | `api.php:179` |
| POST | `/api/admin/pos/licences/{licence}/renew` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@renew` | `api.php:184` |
| DELETE | `/api/admin/pos/licences/{licence}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@destroy` | `api.php:187` |
| POST | `/api/admin/pos/licences/{licence}/revoke` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@revoke` | `api.php:188` |
| POST | `/api/admin/pos/licences/{licence}/suspend` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@suspend` | `api.php:191` |
| POST | `/api/admin/pos/licences/{licence}/resume` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@resume` | `api.php:192` |
| POST | `/api/admin/pos/licences/{licence}/expire` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@expire` | `api.php:193` |
| GET | `/api/admin/pos/licences/{licence}/terminals` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@terminals` | `api.php:194` |
| GET | `/api/admin/pos/licences/{licence}/download` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:licences.manage` | `Admin\LicenceController@download` | `api.php:197` |
| GET | `/api/admin/pos/terminals` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.view` | `Admin\PosFleetController@index` | `api.php:206` |
| GET | `/api/admin/pos/terminals/{terminal}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.view` | `Admin\PosFleetController@show` | `api.php:207` |
| GET | `/api/admin/restaurants/{restaurant}/terminals` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.view` | `Admin\RestaurantTerminalController@index` | `api.php:219` |
| POST | `/api/admin/restaurants/{restaurant}/terminals` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.manage` | `Admin\RestaurantTerminalController@store` | `api.php:222` |
| POST | `/api/admin/restaurants/{restaurant}/terminals/{terminal}/pairing-code` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.manage` | `Admin\RestaurantTerminalController@pairingCode` | `api.php:224` |
| POST | `/api/admin/restaurants/{restaurant}/terminals/{terminal}/revoke` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.manage` | `Admin\RestaurantTerminalController@revoke` | `api.php:225` |
| DELETE | `/api/admin/restaurants/{restaurant}/terminals/{terminal}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:pos_fleet.manage` | `Admin\RestaurantTerminalController@destroy` | `api.php:228` |
| GET | `/api/admin/landing-content` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:landing.manage` | `Admin\LandingContentController@show` | `api.php:233` |
| PUT | `/api/admin/landing-content` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:landing.manage` | `Admin\LandingContentController@update` | `api.php:234` |
| GET | `/api/admin/leads` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:leads.manage` | `Admin\LeadController@index` | `api.php:239` |
| GET | `/api/admin/leads/export` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:leads.manage` | `Admin\LeadController@export` | `api.php:240` |
| PATCH | `/api/admin/leads/{lead}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:leads.manage` | `Admin\LeadController@update` | `api.php:241` |
| GET | `/api/admin/audit-logs` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:audit.view` | `Admin\AuditLogController@index` | `api.php:246` |
| GET | `/api/admin/audit-logs/filters` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:audit.view` | `Admin\AuditLogController@filters` | `api.php:247` |
| GET | `/api/admin/audit-logs/files` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:audit.view` | `Admin\AuditLogController@files` | `api.php:249` |
| GET | `/api/admin/audit-logs/files/{date}` | `auth:jwt`, `role:SUPER_ADMIN,ADMIN,MODERATOR,SALES,SUPPORT`, `can:audit.view` | `Admin\AuditLogController@download` | `api.php:250` |
| POST | `/api/dashboard/push/token` | `auth:jwt`, `role:<computed>` | `Dashboard\PushTokenController@store` | `api.php:276` |
| DELETE | `/api/dashboard/push/token` | `auth:jwt`, `role:<computed>` | `Dashboard\PushTokenController@destroy` | `api.php:277` |
| GET | `/api/dashboard/pulse` | `auth:jwt`, `role:<computed>` | `Dashboard\PulseController@index` | `api.php:283` |
| GET | `/api/dashboard/notifications` | `auth:jwt`, `role:<computed>` | `Dashboard\NotificationController@index` | `api.php:288` |
| GET | `/api/dashboard/notifications/unread-count` | `auth:jwt`, `role:<computed>` | `Dashboard\NotificationController@unreadCount` | `api.php:289` |
| POST | `/api/dashboard/notifications/read-all` | `auth:jwt`, `role:<computed>` | `Dashboard\NotificationController@markAllRead` | `api.php:290` |
| PATCH | `/api/dashboard/notifications/{notification}/read` | `auth:jwt`, `role:<computed>` | `Dashboard\NotificationController@markRead` | `api.php:291` |
| POST | `/api/dashboard/geo/resolve-map-link` | `auth:jwt`, `role:<computed>` | `Dashboard\MapLinkController@resolve` | `api.php:297` |
| GET | `/api/dashboard/roles` | `auth:jwt`, `role:<computed>`, `can:staff.view` | `Dashboard\RoleController@index` | `api.php:303` |
| GET | `/api/dashboard/roles/capabilities` | `auth:jwt`, `role:<computed>`, `can:staff.view` | `Dashboard\RoleController@capabilities` | `api.php:304` |
| GET | `/api/dashboard/roles/{role}` | `auth:jwt`, `role:<computed>`, `can:staff.view` | `Dashboard\RoleController@show` | `api.php:305` |
| GET | `/api/dashboard/staff` | `auth:jwt`, `role:<computed>`, `can:staff.view` | `Dashboard\StaffController@index` | `api.php:306` |
| GET | `/api/dashboard/staff/{staff}` | `auth:jwt`, `role:<computed>`, `can:staff.view` | `Dashboard\StaffController@show` | `api.php:307` |
| POST | `/api/dashboard/roles` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.create` | `Dashboard\RoleController@store` | `api.php:312` |
| PUT | `/api/dashboard/roles/{role}` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.update` | `Dashboard\RoleController@update` | `api.php:313` |
| DELETE | `/api/dashboard/roles/{role}` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.delete` | `Dashboard\RoleController@destroy` | `api.php:314` |
| POST | `/api/dashboard/staff` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.create` | `Dashboard\StaffController@store` | `api.php:316` |
| PUT | `/api/dashboard/staff/{staff}` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.update` | `Dashboard\StaffController@update` | `api.php:317` |
| DELETE | `/api/dashboard/staff/{staff}` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.delete` | `Dashboard\StaffController@destroy` | `api.php:318` |
| POST | `/api/dashboard/staff/{staff}/reset-password` | `auth:jwt`, `role:<computed>`, `can:staff.view`, `subscription.writable`, `can:staff.update`, `throttle:10,1` | `Dashboard\StaffController@resetPassword` | `api.php:320` |
| GET | `/api/dashboard/restaurant` | `auth:jwt`, `role:<computed>`, `can:settings.view` | `Dashboard\RestaurantProfileController@show` | `api.php:330` |
| GET | `/api/dashboard/qr` | `auth:jwt`, `role:<computed>`, `can:settings.view` | `Dashboard\DashboardQrController@show` | `api.php:331` |
| GET | `/api/dashboard/qr/download` | `auth:jwt`, `role:<computed>`, `can:settings.view` | `Dashboard\DashboardQrController@download` | `api.php:332` |
| PUT | `/api/dashboard/restaurant` | `auth:jwt`, `role:<computed>`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\RestaurantProfileController@update` | `api.php:334` |
| GET | `/api/dashboard/stats` | `auth:jwt`, `role:<computed>`, `can:analytics.view` | `Dashboard\StatsController@index` | `api.php:342` |
| GET | `/api/dashboard/insights` | `auth:jwt`, `role:<computed>`, `can:analytics.view` | `Dashboard\InsightsController@index` | `api.php:343` |
| GET | `/api/dashboard/branches` | `auth:jwt`, `role:<computed>`, `can:branches.list` | `Dashboard\BranchController@index` | `api.php:351` |
| GET | `/api/dashboard/branches/{branch}/presence` | `auth:jwt`, `role:<computed>`, `can:branches.view` | `Dashboard\BranchController@presence` | `api.php:355` |
| POST | `/api/dashboard/branches` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:branches.create`, `feature:multi_branch` | `Dashboard\BranchController@store` | `api.php:361` |
| PUT | `/api/dashboard/branches/{branch}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:branches.update` | `Dashboard\BranchController@update` | `api.php:365` |
| PUT | `/api/dashboard/branches/{branch}/presence/egress-ips` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:branches.update` | `Dashboard\BranchController@updateEgressIps` | `api.php:368` |
| PATCH | `/api/dashboard/branches/{branch}/status` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:branches.update` | `Dashboard\BranchController@toggleOpen` | `api.php:369` |
| DELETE | `/api/dashboard/branches/{branch}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:branches.delete` | `Dashboard\BranchController@destroy` | `api.php:372` |
| GET | `/api/dashboard/combos` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\ComboController@index` | `api.php:379` |
| GET | `/api/dashboard/categories` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\CategoryController@index` | `api.php:380` |
| GET | `/api/dashboard/categories/{category}` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\CategoryController@show` | `api.php:381` |
| GET | `/api/dashboard/items` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\MenuItemController@index` | `api.php:382` |
| GET | `/api/dashboard/option-groups` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\OptionGroupController@index` | `api.php:383` |
| GET | `/api/dashboard/option-groups/{optionGroup}` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\OptionGroupController@show` | `api.php:384` |
| GET | `/api/dashboard/items/export` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\MenuExportController@export` | `api.php:388` |
| GET | `/api/dashboard/items/{item}` | `auth:jwt`, `role:<computed>`, `can:menu.view` | `Dashboard\MenuItemController@show` | `api.php:389` |
| POST | `/api/dashboard/combos` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.create` | `Dashboard\ComboController@store` | `api.php:393` |
| POST | `/api/dashboard/categories` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.create` | `Dashboard\CategoryController@store` | `api.php:394` |
| POST | `/api/dashboard/option-groups` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.create` | `Dashboard\OptionGroupController@store` | `api.php:395` |
| POST | `/api/dashboard/items` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.create` | `Dashboard\MenuItemController@store` | `api.php:396` |
| POST | `/api/dashboard/items/import` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.create`, `can:menu.update` | `Dashboard\MenuImportController@import` | `api.php:399` |
| PUT | `/api/dashboard/combos/{combo}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\ComboController@update` | `api.php:404` |
| PATCH | `/api/dashboard/combos/{combo}/status` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\ComboController@toggleStatus` | `api.php:405` |
| PATCH | `/api/dashboard/categories/reorder` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\CategoryController@reorder` | `api.php:407` |
| PUT | `/api/dashboard/categories/{category}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\CategoryController@update` | `api.php:408` |
| PATCH | `/api/dashboard/categories/{category}/status` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\CategoryController@toggleStatus` | `api.php:409` |
| PUT | `/api/dashboard/option-groups/{optionGroup}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\OptionGroupController@update` | `api.php:411` |
| PATCH | `/api/dashboard/items/reorder` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\MenuItemController@reorder` | `api.php:413` |
| PUT | `/api/dashboard/items/{item}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\MenuItemController@update` | `api.php:414` |
| PATCH | `/api/dashboard/items/{item}/availability` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.update` | `Dashboard\MenuItemController@toggleAvailability` | `api.php:415` |
| DELETE | `/api/dashboard/combos/{combo}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\ComboController@destroy` | `api.php:419` |
| DELETE | `/api/dashboard/categories/bulk` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\CategoryController@bulkDestroy` | `api.php:420` |
| DELETE | `/api/dashboard/categories/{category}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\CategoryController@destroy` | `api.php:421` |
| DELETE | `/api/dashboard/option-groups/{optionGroup}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\OptionGroupController@destroy` | `api.php:422` |
| DELETE | `/api/dashboard/items/bulk` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\MenuItemController@bulkDestroy` | `api.php:423` |
| DELETE | `/api/dashboard/items/{item}` | `auth:jwt`, `role:<computed>`, `subscription.writable`, `can:menu.delete` | `Dashboard\MenuItemController@destroy` | `api.php:424` |
| GET | `/api/dashboard/customers` | `auth:jwt`, `role:<computed>`, `can:customers.view` | `Dashboard\CustomerController@index` | `api.php:434` |
| GET | `/api/dashboard/customers/{customer}` | `auth:jwt`, `role:<computed>`, `can:customers.view` | `Dashboard\CustomerController@show` | `api.php:435` |
| GET | `/api/dashboard/orders` | `auth:jwt`, `role:<computed>`, `feature:system_ordering\|pos`, `can:orders.read` | `Dashboard\OrderController@index` | `api.php:451` |
| GET | `/api/dashboard/orders/new-count` | `auth:jwt`, `role:<computed>`, `feature:system_ordering\|pos`, `can:orders.read` | `Dashboard\OrderController@newCount` | `api.php:452` |
| PATCH | `/api/dashboard/orders/{order}/status` | `auth:jwt`, `role:<computed>`, `feature:system_ordering\|pos`, `can:orders.update` | `Dashboard\OrderController@updateStatus` | `api.php:454` |
| GET | `/api/dashboard/tables/live` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.live` | `Dashboard\TableController@live` | `api.php:465` |
| GET | `/api/dashboard/dining-areas` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.view` | `Dashboard\DiningAreaController@index` | `api.php:468` |
| GET | `/api/dashboard/tables` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.view` | `Dashboard\TableController@index` | `api.php:469` |
| GET | `/api/dashboard/tables/{table}/qr` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.view` | `Dashboard\TableController@qr` | `api.php:470` |
| GET | `/api/dashboard/tables/{table}/qr/download` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.view` | `Dashboard\TableController@qrDownload` | `api.php:471` |
| POST | `/api/dashboard/tables/qr/download-bulk` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.view` | `Dashboard\TableController@qrDownloadBulk` | `api.php:473` |
| POST | `/api/dashboard/tables/{table}/visit/finish` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `can:tables.update` | `Dashboard\TableController@finishVisit` | `api.php:479` |
| POST | `/api/dashboard/dining-areas` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.create` | `Dashboard\DiningAreaController@store` | `api.php:484` |
| POST | `/api/dashboard/tables` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.create` | `Dashboard\TableController@store` | `api.php:485` |
| POST | `/api/dashboard/tables/bulk` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.create` | `Dashboard\TableController@bulkStore` | `api.php:486` |
| PUT | `/api/dashboard/dining-areas/{area}` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.update` | `Dashboard\DiningAreaController@update` | `api.php:490` |
| PATCH | `/api/dashboard/dining-areas/{area}/status` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.update` | `Dashboard\DiningAreaController@toggleStatus` | `api.php:491` |
| PUT | `/api/dashboard/tables/{table}` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.update` | `Dashboard\TableController@update` | `api.php:492` |
| PATCH | `/api/dashboard/tables/{table}/status` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.update` | `Dashboard\TableController@toggleStatus` | `api.php:493` |
| POST | `/api/dashboard/tables/{table}/qr/regenerate` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.update` | `Dashboard\TableController@regenerateQr` | `api.php:496` |
| DELETE | `/api/dashboard/dining-areas/{area}` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.delete` | `Dashboard\DiningAreaController@destroy` | `api.php:500` |
| DELETE | `/api/dashboard/tables/bulk` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.delete` | `Dashboard\TableController@bulkDestroy` | `api.php:501` |
| DELETE | `/api/dashboard/tables/{table}` | `auth:jwt`, `role:<computed>`, `feature:table_management`, `subscription.writable`, `can:tables.delete` | `Dashboard\TableController@destroy` | `api.php:502` |
| GET | `/api/dashboard/bill-requests` | `auth:jwt`, `role:<computed>`, `feature:bill_requests`, `can:bills.read` | `Dashboard\BillRequestController@index` | `api.php:514` |
| GET | `/api/dashboard/bill-requests/new-count` | `auth:jwt`, `role:<computed>`, `feature:bill_requests`, `can:bills.read` | `Dashboard\BillRequestController@newCount` | `api.php:515` |
| PATCH | `/api/dashboard/bill-requests/{bill}/status` | `auth:jwt`, `role:<computed>`, `feature:bill_requests`, `can:bills.update`, `subscription.writable` | `Dashboard\BillRequestController@updateStatus` | `api.php:518` |
| GET | `/api/dashboard/reviews` | `auth:jwt`, `role:<computed>`, `feature:internal_reviews`, `can:reviews.view` | `Dashboard\ReviewController@index` | `api.php:529` |
| GET | `/api/dashboard/reviews/summary` | `auth:jwt`, `role:<computed>`, `feature:internal_reviews`, `can:reviews.view` | `Dashboard\ReviewController@summary` | `api.php:530` |
| GET | `/api/dashboard/reviews/{review}` | `auth:jwt`, `role:<computed>`, `feature:internal_reviews`, `can:reviews.view` | `Dashboard\ReviewController@show` | `api.php:531` |
| PATCH | `/api/dashboard/reviews/{review}/status` | `auth:jwt`, `role:<computed>`, `feature:internal_reviews`, `can:reviews.update`, `subscription.writable` | `Dashboard\ReviewController@updateStatus` | `api.php:535` |
| POST | `/api/dashboard/reviews/{review}/notes` | `auth:jwt`, `role:<computed>`, `feature:internal_reviews`, `can:reviews.update`, `subscription.writable` | `Dashboard\ReviewController@addNote` | `api.php:536` |
| GET | `/api/dashboard/reports/products-by-time` | `auth:jwt`, `role:<computed>`, `feature:product_analytics`, `can:reports.view` | `Dashboard\ReportController@productsByTime` | `api.php:545` |
| GET | `/api/dashboard/reports/products-by-time/export` | `auth:jwt`, `role:<computed>`, `feature:product_analytics`, `can:reports.view` | `Dashboard\ReportController@export` | `api.php:546` |
| GET | `/api/dashboard/reports/dining-areas` | `auth:jwt`, `role:<computed>`, `feature:product_analytics`, `can:reports.view` | `Dashboard\ReportController@diningAreas` | `api.php:547` |
| GET | `/api/dashboard/units` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\UnitController@index` | `api.php:584` |
| GET | `/api/dashboard/units/{unit}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\UnitController@show` | `api.php:585` |
| GET | `/api/dashboard/suppliers` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierController@index` | `api.php:586` |
| GET | `/api/dashboard/suppliers/balances` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierAccountController@balances` | `api.php:588` |
| GET | `/api/dashboard/suppliers/{supplier}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierController@show` | `api.php:589` |
| GET | `/api/dashboard/suppliers/{supplier}/account` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierAccountController@account` | `api.php:590` |
| GET | `/api/dashboard/supplier-invoices` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierInvoiceController@index` | `api.php:591` |
| GET | `/api/dashboard/supplier-invoices/{supplierInvoice}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierInvoiceController@show` | `api.php:592` |
| GET | `/api/dashboard/supplier-payments` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierPaymentController@index` | `api.php:593` |
| GET | `/api/dashboard/supplier-payments/{supplierPayment}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierPaymentController@show` | `api.php:594` |
| GET | `/api/dashboard/purchasing/drawer-payouts` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\SupplierPaymentController@drawerPayouts` | `api.php:596` |
| GET | `/api/dashboard/purchasing/lookups` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\PurchasingLookupController@index` | `api.php:599` |
| GET | `/api/dashboard/stock-items` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\StockItemController@index` | `api.php:600` |
| GET | `/api/dashboard/stock-items/{stockItem}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\StockItemController@show` | `api.php:601` |
| GET | `/api/dashboard/stock-items/{stockItem}/movements` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\StockItemController@movements` | `api.php:602` |
| GET | `/api/dashboard/stock-levels` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\StockLevelController@index` | `api.php:604` |
| GET | `/api/dashboard/purchase-orders` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\PurchaseOrderController@index` | `api.php:605` |
| GET | `/api/dashboard/purchase-orders/{purchaseOrder}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage` | `Dashboard\PurchaseOrderController@show` | `api.php:606` |
| POST | `/api/dashboard/units` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\UnitController@store` | `api.php:609` |
| PUT | `/api/dashboard/units/{unit}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\UnitController@update` | `api.php:611` |
| POST | `/api/dashboard/suppliers` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierController@store` | `api.php:612` |
| PUT | `/api/dashboard/suppliers/{supplier}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierController@update` | `api.php:613` |
| DELETE | `/api/dashboard/suppliers/{supplier}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierController@destroy` | `api.php:614` |
| POST | `/api/dashboard/stock-items` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\StockItemController@store` | `api.php:617` |
| PUT | `/api/dashboard/stock-items/{stockItem}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\StockItemController@update` | `api.php:618` |
| POST | `/api/dashboard/purchase-orders` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@store` | `api.php:619` |
| PUT | `/api/dashboard/purchase-orders/{purchaseOrder}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@update` | `api.php:621` |
| POST | `/api/dashboard/purchase-orders/{purchaseOrder}/send` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@send` | `api.php:622` |
| POST | `/api/dashboard/purchase-orders/{purchaseOrder}/cancel` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@cancel` | `api.php:624` |
| POST | `/api/dashboard/purchase-orders/{purchaseOrder}/receipts` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@receive` | `api.php:625` |
| POST | `/api/dashboard/stock-adjustments` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\StockAdjustmentController@store` | `api.php:628` |
| POST | `/api/dashboard/purchase-orders/{purchaseOrder}/close` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\PurchaseOrderController@closeShort` | `api.php:631` |
| POST | `/api/dashboard/supplier-invoices` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierInvoiceController@store` | `api.php:633` |
| PUT | `/api/dashboard/supplier-invoices/{supplierInvoice}` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierInvoiceController@update` | `api.php:634` |
| POST | `/api/dashboard/supplier-invoices/{supplierInvoice}/void` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierInvoiceController@void` | `api.php:635` |
| POST | `/api/dashboard/supplier-payments` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierPaymentController@store` | `api.php:637` |
| POST | `/api/dashboard/supplier-payments/{supplierPayment}/void` | `auth:jwt`, `role:<computed>`, `feature:purchasing`, `can:purchase.manage`, `subscription.writable` | `Dashboard\SupplierPaymentController@void` | `api.php:638` |
| GET | `/api/dashboard/pos/terminals` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision` | `Dashboard\PosTerminalController@index` | `api.php:659` |
| POST | `/api/dashboard/pos/terminals` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision`, `subscription.writable` | `Dashboard\PosTerminalController@store` | `api.php:662` |
| POST | `/api/dashboard/pos/terminals/{terminal}/pairing-code` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision`, `subscription.writable`, `throttle:10,1` | `Dashboard\PosTerminalController@pairingCode` | `api.php:663` |
| POST | `/api/dashboard/pos/terminals/{terminal}/revoke` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision`, `subscription.writable` | `Dashboard\PosTerminalController@revoke` | `api.php:665` |
| DELETE | `/api/dashboard/pos/terminals/{terminal}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision`, `subscription.writable` | `Dashboard\PosTerminalController@destroy` | `api.php:669` |
| GET | `/api/dashboard/receipt-profiles` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view` | `Dashboard\ReceiptProfileController@index` | `api.php:683` |
| GET | `/api/dashboard/tax-rules` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view` | `Dashboard\TaxRuleController@index` | `api.php:685` |
| GET | `/api/dashboard/charges` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view` | `Dashboard\ChargeController@index` | `api.php:686` |
| GET | `/api/dashboard/tender-types` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view` | `Dashboard\TenderTypeController@index` | `api.php:687` |
| PUT | `/api/dashboard/receipt-profiles/{branch}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\ReceiptProfileController@update` | `api.php:690` |
| POST | `/api/dashboard/tax-rules` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TaxRuleController@store` | `api.php:692` |
| PUT | `/api/dashboard/tax-rules/{taxRule}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TaxRuleController@update` | `api.php:693` |
| DELETE | `/api/dashboard/tax-rules/{taxRule}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TaxRuleController@destroy` | `api.php:694` |
| POST | `/api/dashboard/charges` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\ChargeController@store` | `api.php:695` |
| PUT | `/api/dashboard/charges/{charge}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\ChargeController@update` | `api.php:696` |
| DELETE | `/api/dashboard/charges/{charge}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\ChargeController@destroy` | `api.php:697` |
| POST | `/api/dashboard/tender-types` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TenderTypeController@store` | `api.php:698` |
| PUT | `/api/dashboard/tender-types/{tenderType}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TenderTypeController@update` | `api.php:699` |
| DELETE | `/api/dashboard/tender-types/{tenderType}` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:settings.view`, `can:settings.update`, `subscription.writable` | `Dashboard\TenderTypeController@destroy` | `api.php:701` |
| PUT | `/api/dashboard/staff/{staff}/pin` | `auth:jwt`, `role:<computed>`, `feature:pos`, `subscription.writable`, `throttle:10,1` | `Dashboard\PosPinController@update` | `api.php:709` |
| DELETE | `/api/dashboard/staff/{staff}/pin` | `auth:jwt`, `role:<computed>`, `feature:pos`, `subscription.writable`, `throttle:10,1` | `Dashboard\PosPinController@destroy` | `api.php:710` |
| POST | `/api/pos/licence/activate` | `throttle:licence-activate` | `Pos\LicenceController@activate` | `api.php:737` |
| GET | `/api/pos/licence/issuer` | `throttle:60,1` | `Pos\LicenceController@issuer` | `api.php:742` |
| GET | `/api/pos/licence/current` | `pos.device:no-feature`, `throttle:60,1` | `Pos\LicenceController@current` | `api.php:745` |
| POST | `/api/pos/license/check` | `pos.device:no-feature`, `throttle:60,1` | `Pos\LicenceController@check` | `api.php:752` |
| POST | `/api/pos/terminals/claim` | `throttle:pos-claim` | `Pos\TerminalController@claim` | `api.php:778` |
| POST | `/api/pos/terminals/register` | `auth:jwt`, `role:<computed>`, `feature:pos`, `can:pos.provision`, `throttle:10,1` | `Pos\TerminalController@register` | `api.php:781` |
| POST | `/api/pos/terminals/heartbeat` | `pos.device:no-feature`, `throttle:120,1` | `Pos\TerminalController@heartbeat` | `api.php:784` |
| GET | `/api/pos/bootstrap` | `pos.device`, `throttle:240,1` | `Pos\BootstrapController@show` | `api.php:788` |
| POST | `/api/pos/terminals/rotate-token` | `pos.device`, `throttle:240,1` | `Pos\TerminalController@rotateToken` | `api.php:789` |
| GET | `/api/pos/orders/by-client-id/{uuid}` | `pos.device`, `throttle:240,1` | `Pos\OrderController@byClientId` | `api.php:793` |
| POST | `/api/pos/orders` | `pos.device`, `throttle:240,1` | `Pos\OrderController@store` | `api.php:794` |
| POST | `/api/pos/orders/{order}/payments` | `pos.device`, `throttle:240,1` | `Pos\OrderController@storePayment` | `api.php:795` |
| GET | `/api/pos/refunds/by-client-id/{uuid}` | `pos.device`, `throttle:240,1` | `Pos\RefundController@byClientId` | `api.php:804` |
| POST | `/api/pos/refunds` | `pos.device`, `throttle:240,1` | `Pos\RefundController@store` | `api.php:805` |
| POST | `/api/pos/customers` | `pos.device`, `throttle:240,1` | `Pos\CustomerController@store` | `api.php:812` |
| GET | `/api/pos/shifts/current` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@current` | `api.php:814` |
| POST | `/api/pos/shifts` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@open` | `api.php:815` |
| POST | `/api/pos/shifts/{shift}/close` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@close` | `api.php:816` |
| GET | `/api/pos/shifts/{shift}/report` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@report` | `api.php:817` |
| POST | `/api/pos/cash-movements` | `pos.device`, `throttle:240,1` | `Pos\ShiftController@cashMovement` | `api.php:818` |
| POST | `/api/uploads/image` | `auth:jwt`, `throttle:60,1` | `UploadController@store` | `api.php:826` |
| GET | `/api/public/restaurants/{slug}/menu` | `throttle:120,1` | `Public\PublicMenuApiController@show` | `api.php:834` |
| GET | `/api/public/landing-content` | `throttle:120,1` | `Public\LandingContentController@show` | `api.php:837` |
| POST | `/api/public/signup` | `throttle:5,10` | `Public\SignupController@store` | `api.php:841` |
| POST | `/api/public/leads` | `throttle:5,10` | `Public\LeadController@store` | `api.php:846` |
| POST | `/api/public/restaurants/{slug}/orders` | `throttle:20,1` | `Public\PublicOrderController@store` | `api.php:851` |
| GET | `/api/public/restaurants/{slug}/orders/{id}/status` | `throttle:60,1` | `Public\PublicOrderController@status` | `api.php:856` |
| POST | `/api/public/restaurants/{slug}/customers` | `throttle:20,1` | `Public\PublicCustomerController@store` | `api.php:861` |
| GET | `/api/public/restaurants/{slug}/branding` | `throttle:120,1` | `Public\RestaurantBrandingController@show` | `api.php:864` |
| GET | `/api/public/tables/{token}` | `throttle:120,1` | `Public\PublicTableController@show` | `api.php:868` |
| POST | `/api/public/tables/{token}/sessions` | `throttle:30,1` | `Public\PublicTableController@createSession` | `api.php:870` |
| POST | `/api/public/sessions/{sessionToken}/bill-requests` | `throttle:20,1` | `Public\PublicBillRequestController@store` | `api.php:874` |
| GET | `/api/public/bill-requests/{token}` | `throttle:60,1` | `Public\PublicBillRequestController@show` | `api.php:876` |
| PATCH | `/api/public/bill-requests/{token}/cancel` | `throttle:20,1` | `Public\PublicBillRequestController@cancel` | `api.php:878` |
| POST | `/api/public/restaurants/{slug}/reviews` | `throttle:10,1` | `Public\PublicReviewController@store` | `api.php:882` |
| GET | `/api/public/restaurants/{slug}/qr` | `throttle:120,1` | `Public\RestaurantQrController@show` | `api.php:885` |
| GET | `/menu/{path?}` | - | `Public\MenuShellController@show` | `web.php:17` |
| GET | `/r/{slug}` | - | `Public\MenuShellController@legacy` | `web.php:21` |
| GET | `/sitemap.xml` | - | `Public\SitemapController@index` | `web.php:24` |
