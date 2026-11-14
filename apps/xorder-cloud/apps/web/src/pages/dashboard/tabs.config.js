// Tabs for screens that sit behind one sidebar entry. Every tab here shares
// the same server gate (feature:purchasing + can:purchase.manage), so no
// per-tab filtering is needed. `match` keeps a tab lit on its detail pages.

export const PURCHASING_TABS = [
    { to: { name: 'dashboard.purchasing.orders' }, labelKey: 'nav.purchase_orders', match: ['dashboard.purchasing.order'] },
    { to: { name: 'dashboard.purchasing.invoices' }, labelKey: 'nav.supplier_invoices', match: ['dashboard.purchasing.invoice'] },
    { to: { name: 'dashboard.purchasing.payments' }, labelKey: 'nav.supplier_payments', match: ['dashboard.purchasing.payment'] },
]

export const STOCK_TABS = [
    { to: { name: 'dashboard.inventory.stock' }, labelKey: 'nav.stock', match: ['dashboard.inventory.stock', 'dashboard.inventory.movements'] },
    { to: { name: 'dashboard.inventory.items' }, labelKey: 'nav.stock_items', match: ['dashboard.inventory.items'] },
]
