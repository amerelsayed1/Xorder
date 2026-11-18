// The Settings area's own sub-menu — one declarative schema, same shape and
// same two gates as `nav.config.js`:
//
//   feature     did this restaurant buy it (plan feature flag)
//   capability  may this person do it (tenant capability)
//
// Settings used to be five separate entries in the main sidebar. They are now
// one entry that opens a shell, and this file is what both ends read: the
// sidebar asks "is ANY section visible" before showing that entry, and the
// shell renders the sections that survive the same filter. Keeping it in one
// place is what stops the sidebar from offering a settings screen with nothing
// in it.
//
// Route *names* are unchanged from when these were top-level pages, so every
// existing RouterLink keeps working — only the URLs moved under /settings.

export const SETTINGS_GROUPS = [
    {
        key: 'account',
        labelKey: 'settings_shell.group_account',
        items: [
            { key: 'profile', labelKey: 'nav.profile', icon: 'pi pi-cog', to: { name: 'dashboard.profile' }, capability: 'settings.view' },
            // No gate: every signed-in user may change their own password.
            { key: 'password', labelKey: 'profile.change_password', icon: 'pi pi-lock', to: { name: 'dashboard.password' } },
        ],
    },
    // Set up once, rarely touched — so they live here rather than in the
    // sidebar. Tables stays in the sidebar's Main section: staff use it all
    // day. Staff and roles moved the other way, to the sidebar's Team section.
    {
        key: 'place',
        labelKey: 'settings_shell.group_place',
        items: [
            { key: 'branches', labelKey: 'nav.branches', icon: 'pi pi-map-marker', to: { name: 'dashboard.branches' }, feature: 'multi_branch', capability: 'branches.view' },
            { key: 'areas', labelKey: 'nav.areas', icon: 'pi pi-th-large', to: { name: 'dashboard.areas' }, feature: 'table_management', capability: 'tables.view' },
            // The one standing QR for guest paging (the client types the number on their slip).
            { key: 'pager_qr', labelKey: 'nav.pager_qr', icon: 'pi pi-qrcode', to: { name: 'dashboard.pager_qr' }, feature: 'guest_paging', capability: 'settings.view' },
        ],
    },
    {
        key: 'pos',
        labelKey: 'settings_shell.group_pos',
        items: [
            { key: 'devices', labelKey: 'nav.pos_terminals', icon: 'pi pi-desktop', to: { name: 'dashboard.pos.terminals' }, feature: 'pos', capability: 'pos.provision' },
            { key: 'taxes', labelKey: 'nav.pos_money', icon: 'pi pi-percentage', to: { name: 'dashboard.pos.money' }, feature: 'pos', capability: 'settings.view' },
            { key: 'payment_methods', labelKey: 'nav.pos_payment_methods', icon: 'pi pi-wallet', to: { name: 'dashboard.pos.payment_methods' }, feature: 'pos', capability: 'settings.view' },
            { key: 'receipt', labelKey: 'nav.pos_receipt', icon: 'pi pi-receipt', to: { name: 'dashboard.pos.receipt' }, feature: 'pos', capability: 'settings.view' },
        ],
    },
    {
        key: 'purchasing',
        labelKey: 'settings_shell.group_purchasing',
        items: [
            { key: 'units', labelKey: 'nav.units', icon: 'pi pi-tag', to: { name: 'dashboard.inventory.units' }, feature: 'purchasing', capability: 'purchase.manage' },
        ],
    },
]

// Every route name a settings section can show, for the sidebar entry's active
// state: the shell's index route (Profile) is not a parent of its siblings, so
// the link alone would go dark on every section but Profile. Prefix-matched, so
// create/edit pages under a section count too.
export const SETTINGS_ROUTE_NAMES = SETTINGS_GROUPS.flatMap((g) => g.items.map((i) => i.to.name))

const allowed = (features, can) => (item) =>
    (!item.feature || features.includes(item.feature))
    && (!item.capability || can(item.capability))

// Groups with their unreachable items dropped, and empty groups dropped whole.
export function buildSettingsNav({ features = [], can = () => true } = {}) {
    const keep = allowed(features, can)
    const out = []
    for (const group of SETTINGS_GROUPS) {
        const items = group.items.filter(keep)
        if (items.length) out.push({ ...group, items })
    }
    return out
}

// Flat list, in sub-menu order — used to pick where bare /settings lands.
export function visibleSettingsSections(ctx) {
    return buildSettingsNav(ctx).flatMap((g) => g.items)
}
