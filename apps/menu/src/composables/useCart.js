import { ref, computed, watch } from 'vue'

export function useCart(slug = '') {
    const storageKey = `xorder-cart:${slug}`

    function restore() {
        try {
            const parsed = JSON.parse(localStorage.getItem(storageKey) || '[]')
            return Array.isArray(parsed) ? parsed : []
        } catch {
            return []
        }
    }

    const cart = ref(restore())

    // Persist across refreshes — diners on restaurant WiFi lose the page
    // constantly, and rebuilding a cart from scratch kills the order.
    watch(cart, (lines) => {
        try {
            localStorage.setItem(storageKey, JSON.stringify(lines))
        } catch {
            /* private mode / storage full — cart just won't survive a refresh */
        }
    }, { deep: true })

    const cartCount = computed(() => cart.value.reduce((n, line) => n + line.qty, 0))
    const cartTotal = computed(() => cart.value.reduce((sum, line) => sum + line.qty * line.price, 0))

    function addToCart(kind, ref_, groups, qty, note = '') {
        const uid = `${kind}-${ref_.id}-${JSON.stringify(groups)}-${note}`
        const existing = cart.value.find(l => l.uid === uid)
        if (existing) {
            existing.qty += qty
        } else {
            // Snapshot the full item so cart lines and the WhatsApp message
            // can show real names/options (groups only holds indexes).
            cart.value.push({ uid, kind, ref: ref_, groups, qty, note, price: calculateLinePrice(kind, ref_, groups) })
        }
    }

    function removeLine(uid) {
        const idx = cart.value.findIndex(l => l.uid === uid)
        if (idx >= 0) cart.value.splice(idx, 1)
    }

    function bumpLine(uid, delta) {
        const line = cart.value.find(l => l.uid === uid)
        if (!line) return
        line.qty += delta
        if (line.qty <= 0) removeLine(uid)
    }

    function clearCart() {
        cart.value = []
    }

    /** Human-readable labels of the selected options for a cart line. */
    function getLineOptions(line, localize) {
        const groups = (line.kind === 'combo' ? line.ref.groups : line.ref.option_groups) || []
        const labels = []
        groups.forEach((g, gi) => {
            const pool = (line.kind === 'combo' ? g.items : g.options) || []
            selectedIndexes(line.groups[gi]).forEach((oi) => {
                const opt = pool[oi]
                if (opt) labels.push(localize(opt))
            })
        })
        return labels
    }

    function amount(value) {
        const number = Number(value ?? 0)
        return Number.isFinite(number) ? number : 0
    }

    function selectedIndexes(value) {
        if (value == null) return []
        return Array.isArray(value) ? value : [value]
    }

    function calculateLinePrice(kind, item, groups) {
        // Base and add-ons are tracked apart so a variant (size) group can
        // REPLACE the base while regular groups add on top — independent of the
        // order the groups happen to appear in.
        let base = amount(kind === 'combo' ? item.base_price : item.price)
        let addons = 0

        if (kind === 'item' && item.option_groups) {
            item.option_groups.forEach((g, gi) => {
                const picked = selectedIndexes(groups[gi])
                if (g.is_variant) {
                    // Size/portion selector: the chosen option's price is the price.
                    const opt = (g.options || [])[picked[0]]
                    if (opt) base = amount(opt.price)
                    return
                }
                picked.forEach((oi) => {
                    const opt = (g.options || [])[oi]
                    addons += amount(opt?.price)
                })
            })
        }

        let price = base + addons

        if (kind === 'combo' && item.groups) {
            item.groups.forEach((g, gi) => {
                selectedIndexes(groups[gi]).forEach((oi) => {
                    const opt = (g.items || [])[oi]
                    price += amount(opt?.extra_price)
                })
            })
        }

        return price
    }

    return {
        cart,
        cartCount,
        cartTotal,
        addToCart,
        removeLine,
        bumpLine,
        clearCart,
        getLineOptions,
        calculateLinePrice,
    }
}
