// Dashboard sidebar navigation — a declarative, reusable schema.
//
// The UI component (SakaiLayout) knows nothing about which items exist; it just
// renders whatever this schema produces. Each node supports:
//   key        unique id (used for v-for keys and accordion state)
//   labelKey   i18n key resolved at render time
//   icon       PrimeIcons class (e.g. 'pi pi-shopping-bag')
//   to         named-route object for leaf items ({ name: 'dashboard.orders' })
//   end        exact-match active state (only the dashboard home item)
//   permission restaurant feature flag gating visibility (optional)
//   badgeKey   which live badge value to show ('orders' | 'requests')
//   children   nested leaf items → the node renders as a collapsible group
//
// Active state and highlighting are derived in the component from the router,
// so nothing about routes, permissions, or badges is hardcoded in the markup.

export const DASHBOARD_NAV = [
    { key: 'home', labelKey: 'nav.dashboard', icon: 'pi pi-th-large', to: { name: 'dashboard.home' }, end: true },
    { key: 'live', labelKey: 'nav.live', icon: 'pi pi-bolt', to: { name: 'dashboard.live' }, badgeKey: 'live', permissionAny: ['bill_requests', 'system_ordering', 'table_management'] },
    {
        key: 'orders', labelKey: 'nav.group_orders', icon: 'pi pi-shopping-bag',
        children: [
            { key: 'orders.list', labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', to: { name: 'dashboard.orders' }, permission: 'system_ordering' },
        ],
    },
    {
        key: 'menu', labelKey: 'nav.group_menu', icon: 'pi pi-book',
        children: [
            { key: 'items', labelKey: 'nav.items', icon: 'pi pi-list', to: { name: 'dashboard.items' } },
            { key: 'categories', labelKey: 'nav.categories', icon: 'pi pi-tags', to: { name: 'dashboard.categories' } },
            { key: 'extras', labelKey: 'nav.extras', icon: 'pi pi-plus-circle', to: { name: 'dashboard.extras' } },
            { key: 'qr', labelKey: 'nav.qr', icon: 'pi pi-qrcode', to: { name: 'dashboard.qr' } },
        ],
    },
    {
        key: 'place', labelKey: 'nav.group_place', icon: 'pi pi-building',
        children: [
            { key: 'branches', labelKey: 'nav.branches', icon: 'pi pi-map-marker', to: { name: 'dashboard.branches' }, permission: 'multi_branch' },
            { key: 'areas', labelKey: 'nav.areas', icon: 'pi pi-th-large', to: { name: 'dashboard.areas' }, permission: 'table_management' },
            { key: 'tables', labelKey: 'nav.tables', icon: 'pi pi-table', to: { name: 'dashboard.tables' }, permission: 'table_management' },
        ],
    },
    {
        key: 'engagement', labelKey: 'nav.group_engagement', icon: 'pi pi-users',
        children: [
            { key: 'customers', labelKey: 'nav.customers', icon: 'pi pi-user', to: { name: 'dashboard.customers' }, permission: 'customer_tracking' },
            { key: 'reviews', labelKey: 'nav.reviews', icon: 'pi pi-star', to: { name: 'dashboard.reviews' }, permission: 'internal_reviews' },
        ],
    },
    {
        key: 'analytics', labelKey: 'nav.group_analytics', icon: 'pi pi-chart-bar',
        children: [
            { key: 'insights', labelKey: 'nav.insights', icon: 'pi pi-chart-bar', to: { name: 'dashboard.insights' } },
            { key: 'reports.products', labelKey: 'rep.products_title', icon: 'pi pi-chart-line', to: { name: 'dashboard.reports.products' }, permission: 'product_analytics' },
            { key: 'reports.areas', labelKey: 'rep.areas_title', icon: 'pi pi-table', to: { name: 'dashboard.reports.areas' }, permission: 'product_analytics' },
        ],
    },
    {
        key: 'settings', labelKey: 'nav.group_settings', icon: 'pi pi-cog',
        children: [
            { key: 'profile', labelKey: 'nav.profile', icon: 'pi pi-cog', to: { name: 'dashboard.profile' } },
        ],
    },
]

// Resolve the schema against the current feature set and live badge counts:
//   - drops leaf items whose `permission` flag the restaurant doesn't have
//   - hides a group entirely when none of its children are visible
//   - stamps each node's `badge` from `badges[badgeKey]`
export function buildDashboardNav({ features = [], badges = {} } = {}) {
    // A node is visible when it has no `permission` gate (or the flag is held)
    // and, if it declares `permissionAny`, at least one of those flags is held.
    const allowed = (node) => (!node.permission || features.includes(node.permission))
        && (!node.permissionAny || node.permissionAny.some((p) => features.includes(p)))
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
