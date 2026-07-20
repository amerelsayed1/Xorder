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
    {
        key: 'orders', labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', badgeKey: 'orders',
        children: [
            { key: 'orders.list', labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', to: { name: 'dashboard.orders' } },
            { key: 'orders.live', labelKey: 'nav.requests', icon: 'pi pi-bell', to: { name: 'dashboard.requests' }, permission: 'bill_requests', badgeKey: 'requests' },
        ],
    },
    {
        key: 'menu', labelKey: 'nav.group_menu', icon: 'pi pi-book',
        children: [
            { key: 'items', labelKey: 'nav.items', icon: 'pi pi-list', to: { name: 'dashboard.items' } },
            { key: 'categories', labelKey: 'nav.categories', icon: 'pi pi-tags', to: { name: 'dashboard.categories' } },
            { key: 'qr', labelKey: 'nav.qr', icon: 'pi pi-qrcode', to: { name: 'dashboard.qr' } },
        ],
    },
    {
        key: 'place', labelKey: 'nav.group_place', icon: 'pi pi-building',
        children: [
            { key: 'branches', labelKey: 'nav.branches', icon: 'pi pi-map-marker', to: { name: 'dashboard.branches' } },
            { key: 'areas', labelKey: 'nav.areas', icon: 'pi pi-th-large', to: { name: 'dashboard.areas' }, permission: 'table_management' },
            { key: 'tables', labelKey: 'nav.tables', icon: 'pi pi-table', to: { name: 'dashboard.tables' }, permission: 'table_management' },
        ],
    },
    {
        key: 'engagement', labelKey: 'nav.group_engagement', icon: 'pi pi-users',
        children: [
            { key: 'customers', labelKey: 'nav.customers', icon: 'pi pi-user', to: { name: 'dashboard.customers' } },
            { key: 'reviews', labelKey: 'nav.reviews', icon: 'pi pi-star', to: { name: 'dashboard.reviews' }, permission: 'internal_reviews' },
        ],
    },
    {
        key: 'analytics', labelKey: 'nav.group_analytics', icon: 'pi pi-chart-bar',
        children: [
            { key: 'insights', labelKey: 'nav.insights', icon: 'pi pi-chart-bar', to: { name: 'dashboard.insights' } },
            { key: 'reports', labelKey: 'nav.reports', icon: 'pi pi-chart-line', to: { name: 'dashboard.reports' }, permission: 'product_analytics' },
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
    const allowed = (perm) => !perm || features.includes(perm)
    const withBadge = (node) => (node.badgeKey ? { ...node, badge: badges[node.badgeKey] ?? 0 } : node)

    const out = []
    for (const node of DASHBOARD_NAV) {
        if (node.children) {
            const children = node.children.filter((c) => allowed(c.permission)).map(withBadge)
            if (!children.length) continue // hide empty group
            out.push({ ...withBadge(node), children })
        } else if (allowed(node.permission)) {
            out.push(withBadge(node))
        }
    }
    return out
}
