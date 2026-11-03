import { visibleSettingsSections, SETTINGS_ROUTE_NAMES } from './settings/settings.config.js'

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
//   match      route-name prefixes that also mark the item active (one entry
//              standing for a tabbed screen or the settings shell)
//   section    heading whose children are always listed (see SakaiLayout)
//   children   nested leaf items → a section, or a collapsible group
//
// `feature` and `capability` answer different questions and both must pass:
// the first is "did this restaurant buy it", the second is "may this person do
// it". They were one field called `permission` before staff roles existed.
//
// Active state and highlighting are derived in the component from the router,
// so nothing about routes, permissions, or badges is hardcoded in the markup.

export const DASHBOARD_NAV = [
    // Sections are headings with their pages always listed underneath — every
    // page is one click away, unlike the old one-open-at-a-time accordion.
    // Order follows how often a page is used: the floor's daily screens first,
    // set-up last.
    {
        key: 'main', labelKey: 'nav.section_main', section: true,
        children: [
            { key: 'home', labelKey: 'nav.dashboard', icon: 'pi pi-th-large', to: { name: 'dashboard.home' }, end: true },
            { key: 'live', labelKey: 'nav.live', icon: 'pi pi-bolt', to: { name: 'dashboard.live' }, badgeKey: 'live', featureAny: ['bill_requests', 'system_ordering', 'table_management'], capability: 'live.view' },
            // The queue holds online orders AND the till's sales, so a plan with
            // either feature gets the entry (the API gate is the same any-of).
            { key: 'orders', labelKey: 'nav.orders', icon: 'pi pi-shopping-bag', to: { name: 'dashboard.orders' }, badgeKey: 'orders', featureAny: ['system_ordering', 'pos'], capability: 'orders.view' },
            { key: 'tables', labelKey: 'nav.tables', icon: 'pi pi-table', to: { name: 'dashboard.tables' }, feature: 'table_management', capability: 'tables.view' },
        ],
    },
    {
        key: 'menu', labelKey: 'nav.section_menu', section: true,
        children: [
            { key: 'items', labelKey: 'nav.items', icon: 'pi pi-list', to: { name: 'dashboard.items' }, capability: 'menu.view' },
            { key: 'categories', labelKey: 'nav.categories', icon: 'pi pi-tags', to: { name: 'dashboard.categories' }, capability: 'menu.view' },
            { key: 'extras', labelKey: 'nav.extras', icon: 'pi pi-plus-circle', to: { name: 'dashboard.extras' }, capability: 'menu.view' },
        ],
    },
    // Purchasing and inventory (CB-09). `purchasing` is a standalone feature a
    // café or cloud kitchen may buy with no till (owner decision 2026-09-12), so
    // nothing here depends on the `pos` flag. One capability, purchase.manage,
    // covers reads and writes, as on the server. Stock and Purchasing are each
    // one entry over a tabbed screen; `match` keeps the entry lit on every tab.
    {
        key: 'stock', labelKey: 'nav.section_stock', section: true,
        children: [
            // "Received to date", never "on hand": tills don't deduct sales.
            { key: 'inventory.stock', labelKey: 'nav.stock_short', icon: 'pi pi-box', to: { name: 'dashboard.inventory.stock' }, match: ['dashboard.inventory.stock', 'dashboard.inventory.movements', 'dashboard.inventory.items'], feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'purchasing', labelKey: 'nav.purchasing', icon: 'pi pi-shopping-cart', to: { name: 'dashboard.purchasing.orders' }, match: ['dashboard.purchasing.order', 'dashboard.purchasing.invoice', 'dashboard.purchasing.payment'], feature: 'purchasing', capability: 'purchase.manage' },
            { key: 'purchasing.suppliers', labelKey: 'nav.suppliers', icon: 'pi pi-briefcase', to: { name: 'dashboard.purchasing.suppliers' }, match: ['dashboard.purchasing.supplier'], feature: 'purchasing', capability: 'purchase.manage' },
        ],
    },
    {
        key: 'customers', labelKey: 'nav.section_customers', section: true,
        children: [
            { key: 'customers', labelKey: 'nav.customers', icon: 'pi pi-user', to: { name: 'dashboard.customers' }, capability: 'customers.view' },
            { key: 'reviews', labelKey: 'nav.reviews', icon: 'pi pi-star', to: { name: 'dashboard.reviews' }, feature: 'internal_reviews', capability: 'reviews.view' },
        ],
    },
    {
        key: 'reports', labelKey: 'nav.section_reports', section: true,
        children: [
            { key: 'insights', labelKey: 'nav.insights', icon: 'pi pi-chart-bar', to: { name: 'dashboard.insights' }, capability: 'analytics.view' },
            { key: 'reports.products', labelKey: 'rep.products_title', icon: 'pi pi-chart-line', to: { name: 'dashboard.reports.products' }, feature: 'product_analytics', capability: 'reports.view' },
            { key: 'reports.areas', labelKey: 'rep.areas_title', icon: 'pi pi-table', to: { name: 'dashboard.reports.areas' }, feature: 'product_analytics', capability: 'reports.view' },
        ],
    },
    // People are managed often enough (hiring, PINs, shifts) to earn their own
    // section; they used to sit inside the settings shell.
    {
        key: 'team', labelKey: 'nav.section_team', section: true,
        children: [
            { key: 'staff', labelKey: 'nav.staff', icon: 'pi pi-users', to: { name: 'dashboard.staff' }, capability: 'staff.view' },
            { key: 'roles', labelKey: 'nav.roles', icon: 'pi pi-shield', to: { name: 'dashboard.roles' }, capability: 'staff.view' },
        ],
    },
    // Settings is one entry over its own shell (see settings/settings.config.js,
    // which `settingsVisible()` below consults so this entry never opens an
    // empty screen). Profile sits at the bare /settings; a user who cannot
    // open Profile is moved on to the first section they can (settingsIndexGuard).
    {
        key: 'settings', labelKey: 'nav.section_settings', section: true,
        children: [
            { key: 'settings', labelKey: 'nav.restaurant_settings', icon: 'pi pi-cog', to: { name: 'dashboard.profile' }, match: SETTINGS_ROUTE_NAMES, settings: true },
        ],
    },
]

// Resolve the schema against the current feature set, the signed-in user's
// capabilities and the live badge counts:
//   - drops leaf items whose `feature` flag the restaurant doesn't have
//   - drops leaf items whose `capability` the signed-in user doesn't hold
//   - hides a section/group entirely when none of its children are visible
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
