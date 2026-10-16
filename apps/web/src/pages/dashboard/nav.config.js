import { visibleSettingsSections } from './settings/settings.config.js'

// Dashboard sidebar navigation — a declarative, reusable schema.
//
// The UI component (SakaiLayout) knows nothing about which items exist; it just
// renders whatever this schema produces. Each node supports:
//   key        unique id (used for v-for keys and accordion state)
//   labelKey   i18n key resolved at render time
//   icon       PrimeIcons class (e.g. 'pi pi-shopping-bag')
//   to         named-route object for leaf items ({ name: 'dashboard.orders' })
//   end        exact-match active state (only the dashboard home item)
//   feature    restaurant plan feature flag gating visibility (optional)
//   featureAny visible when the restaurant holds ANY of these feature flags
//   capability tenant capability the signed-in user must hold (optional)
//   badgeKey   which live badge value to show ('orders' | 'requests')
//   settings   visible when any settings section is (see settings.config.js)
//   children   nested leaf items → the node renders as a collapsible group
//
// `feature` and `capability` answer different questions and both must pass:
// the first is "did this restaurant buy it", the second is "may this person do
// it". They were one field called `permission` before staff roles existed.
//
// Active state and highlighting are derived in the component from the router,
// so nothing about routes, permissions, or badges is hardcoded in the markup.

export const DASHBOARD_NAV = [
    { key: 'home', labelKey: 'nav.dashboard', icon: 'pi pi-th-large', to: { name: 'dashboard.home' }, end: true },
    { key: 'live', labelKey: 'nav.live', icon: 'pi pi-bolt', to: { name: 'dashboard.live' }, badgeKey: 'live', featureAny: ['bill_requests', 'system_ordering', 'table_management'], capability: 'live.view' },
    {
        key: 'orders', labelKey: 'nav.group_orders', icon: 'pi pi-shopping-bag',
        children: [
            // The queue holds online orders AND the till's sales, so a plan with
            // either feature gets the entry (the API gate is the same any-of).
            { key: 'orders.list', labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', to: { name: 'dashboard.orders' }, featureAny: ['system_ordering', 'pos'], capability: 'orders.view' },
        ],
    },
    {
        key: 'menu', labelKey: 'nav.group_menu', icon: 'pi pi-book',
        children: [
            { key: 'items', labelKey: 'nav.items', icon: 'pi pi-list', to: { name: 'dashboard.items' }, capability: 'menu.view' },
            { key: 'categories', labelKey: 'nav.categories', icon: 'pi pi-tags', to: { name: 'dashboard.categories' }, capability: 'menu.view' },
            { key: 'extras', labelKey: 'nav.extras', icon: 'pi pi-plus-circle', to: { name: 'dashboard.extras' }, capability: 'menu.view' },
        ],
    },
    {
        key: 'place', labelKey: 'nav.group_place', icon: 'pi pi-building',
        children: [
            { key: 'branches', labelKey: 'nav.branches', icon: 'pi pi-map-marker', to: { name: 'dashboard.branches' }, feature: 'multi_branch', capability: 'branches.view' },
            { key: 'areas', labelKey: 'nav.areas', icon: 'pi pi-th-large', to: { name: 'dashboard.areas' }, feature: 'table_management', capability: 'tables.view' },
            { key: 'tables', labelKey: 'nav.tables', icon: 'pi pi-table', to: { name: 'dashboard.tables' }, feature: 'table_management', capability: 'tables.view' },
        ],
    },
    // Purchasing and inventory (CB-09). Operational pages, so they live in the
    // sidebar rather than the settings shell, and deliberately OUTSIDE the
    // "Point of sale & money" settings group: `purchasing` is a standalone
    // feature a café or cloud kitchen may buy with no till (owner decision
    // 2026-09-12), so nothing here depends on the `pos` flag. One capability,
    // purchase.manage, covers reads and writes, as on the server.
    {
        key: 'purchasing', labelKey: 'nav.group_purchasing', icon: 'pi pi-truck',
        children: [
            { key: 'purchasing.orders', labelKey: 'nav.purchase_orders', icon: 'pi pi-file-edit', to: { name: 'dashboard.purchasing.orders' }, feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'purchasing.invoices', labelKey: 'nav.supplier_invoices', icon: 'pi pi-file', to: { name: 'dashboard.purchasing.invoices' }, feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'purchasing.payments', labelKey: 'nav.supplier_payments', icon: 'pi pi-wallet', to: { name: 'dashboard.purchasing.payments' }, feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'purchasing.suppliers', labelKey: 'nav.suppliers', icon: 'pi pi-briefcase', to: { name: 'dashboard.purchasing.suppliers' }, feature: 'purchasing', capability: 'purchase.manage' },
        ],
    },
    {
        key: 'inventory', labelKey: 'nav.group_inventory', icon: 'pi pi-box',
        children: [
            // "Received to date", never "on hand": tills don't deduct sales.
            { key: 'inventory.stock', labelKey: 'nav.stock', icon: 'pi pi-inbox', to: { name: 'dashboard.inventory.stock' }, feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'inventory.items', labelKey: 'nav.stock_items', icon: 'pi pi-list', to: { name: 'dashboard.inventory.items' }, feature: 'purchasing', capability: 'purchase.manage' },
        ],
    },
    {
        key: 'engagement', labelKey: 'nav.group_engagement', icon: 'pi pi-users',
        children: [
            { key: 'customers', labelKey: 'nav.customers', icon: 'pi pi-user', to: { name: 'dashboard.customers' }, capability: 'customers.view' },
            { key: 'reviews', labelKey: 'nav.reviews', icon: 'pi pi-star', to: { name: 'dashboard.reviews' }, feature: 'internal_reviews', capability: 'reviews.view' },
        ],
    },
    {
        key: 'analytics', labelKey: 'nav.group_analytics', icon: 'pi pi-chart-bar',
        children: [
            { key: 'insights', labelKey: 'nav.insights', icon: 'pi pi-chart-bar', to: { name: 'dashboard.insights' }, capability: 'analytics.view' },
            { key: 'reports.products', labelKey: 'rep.products_title', icon: 'pi pi-chart-line', to: { name: 'dashboard.reports.products' }, feature: 'product_analytics', capability: 'reports.view' },
            { key: 'reports.areas', labelKey: 'rep.areas_title', icon: 'pi pi-table', to: { name: 'dashboard.reports.areas' }, feature: 'product_analytics', capability: 'reports.view' },
        ],
    },
    // Settings is one entry, not a group. The five sections it used to list
    // live inside the settings shell now, behind their own sub-menu — see
    // `settings/settings.config.js`, which is also what `settingsVisible()`
    // below consults so this entry never opens an empty screen.
    // Profile sits at the bare /settings, so this resolves to /admin/settings —
    // the URL the sidebar promises. A user who cannot open Profile is moved on
    // to the first section they can (see settingsIndexGuard in the router).
    { key: 'settings', labelKey: 'nav.group_settings', icon: 'pi pi-cog', to: { name: 'dashboard.profile' }, settings: true },
]

// Resolve the schema against the current feature set, the signed-in user's
// capabilities and the live badge counts:
//   - drops leaf items whose `feature` flag the restaurant doesn't have
//   - drops leaf items whose `capability` the signed-in user doesn't hold
//   - hides a group entirely when none of its children are visible
//   - stamps each node's `badge` from `badges[badgeKey]`
//
// `can` defaults to "allowed" so callers that don't pass it (and the owner, who
// holds everything) behave exactly as before staff roles existed.
export function buildDashboardNav({ features = [], badges = {}, can = () => true } = {}) {
    // The Settings entry has no capability of its own: it is reachable when at
    // least one of the sections behind it is. Asking the settings schema keeps
    // that answer in one place instead of duplicating five gates here.
    const settingsVisible = visibleSettingsSections({ features, can }).length > 0
    // A node is visible when it has no `feature` gate (or the flag is held),
    // and, if it declares `featureAny`, at least one of those flags is held,
    // and the signed-in user holds its `capability`.
    const allowed = (node) => (!node.feature || features.includes(node.feature))
        && (!node.featureAny || node.featureAny.some((f) => features.includes(f)))
        && (!node.capability || can(node.capability))
        && (!node.settings || settingsVisible)
    const withBadge = (node) => (node.badgeKey ? { ...node, badge: badges[node.badgeKey] ?? 0 } : node)

    const out = []
    for (const node of DASHBOARD_NAV) {
        if (node.children) {
            const children = node.children.filter(allowed).map(withBadge)
            if (!children.length) continue // hide empty group
            out.push({ ...withBadge(node), children })
        } else if (allowed(node)) {
            out.push(withBadge(node))
        }
    }
    return out
}
