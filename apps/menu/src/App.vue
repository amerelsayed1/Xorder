<script setup>
import { ref, computed, onMounted, onUnmounted, watch, reactive } from 'vue'
import { fetchMenu } from './api.js'

const slug = window.location.hostname.split('.')[0]

const payload = ref(null)
const loading = ref(true)
const error = ref(false)
const unavailable = ref(false)
const locale = ref('ar')
const activeCat = ref('offers')

// cart
const cart = ref([])          // [{ uid, kind, ref, groups, qty }]
const cartDrawer = ref(false)
const navDrawer = ref(false)  // side menu
const view = ref('menu')      // 'menu' | 'branches'

// modal
const modal = ref(null)       // { kind:'item'|'combo', ref }
const sel = reactive({ groups: {} })   // groups[gi] = index | [indices]
const qty = ref(1)

const T = {
    ar: { home: 'الرئيسية', offers: 'العروض', branches: 'الفروع', cart: 'السلة', cart_empty: 'اختر أصنافك من القائمة وسنجهّزها في رسالة طلب جاهزة لإرسالها عبر واتساب',
        required: 'مطلوب', choose: 'اختر', open: 'مفتوح', closed: 'مغلق', add: 'إضافة', from: 'يبدأ من',
        location: 'الموقع', total: 'الإجمالي', order_wa: 'اطلب عبر واتساب', remove: 'حذف',
        unavailable: 'القائمة غير متاحة حالياً', view_cart: 'عرض السلة', new_order: 'طلب جديد', qty: 'الكمية',
        your_details: 'بيانات الطلب', f_name: 'الاسم', f_phone: 'رقم الهاتف', f_address: 'العنوان', f_note: 'ملاحظات' },
    en: { home: 'Home', offers: 'Offers', branches: 'Branches', cart: 'Cart', cart_empty: 'Pick your items and we’ll turn them into a ready order message to send on WhatsApp',
        required: 'Required', choose: 'Choose', open: 'Open', closed: 'Closed', add: 'Add', from: 'From',
        location: 'Location', total: 'Total', order_wa: 'Order via WhatsApp', remove: 'Remove',
        unavailable: 'The menu is currently unavailable', view_cart: 'View cart', new_order: 'New order', qty: 'Qty',
        your_details: 'Order details', f_name: 'Name', f_phone: 'Phone number', f_address: 'Address', f_note: 'Notes' },
}
const t = (k) => T[locale.value][k] || k
const isAr = computed(() => locale.value === 'ar')

const restaurant = computed(() => payload.value?.restaurant || {})
const categories = computed(() => payload.value?.categories || [])
const combos = computed(() => payload.value?.combos || [])
const branches = computed(() => payload.value?.branches || [])
const accent = computed(() => restaurant.value.brand_color || '#ee6c2b')
const sym = computed(() => restaurant.value.currency_symbol || '')
const waDigits = computed(() => (restaurant.value.whatsapp_number || '').replace(/[^0-9]/g, ''))
// Super admin can turn ordering off per restaurant → view-only menu (no cart).
// Treat a missing flag as enabled so older payloads keep working.
const orderingEnabled = computed(() => restaurant.value.ordering_enabled !== false)

function L(obj, field = 'name') {
    if (!obj) return ''
    return obj[`${field}_${locale.value}`] || obj[`${field}_en`] || obj[`${field}_ar`] || ''
}
const money = (v) => `${Number(v).toFixed(2)} ${sym.value}`
const initial = computed(() => (L(restaurant.value) || 'M').charAt(0))
const altName = computed(() => isAr.value ? restaurant.value.name_en : restaurant.value.name_ar)

// Scroll-spy: highlight the category whose section is at the top as you scroll.
function onScroll() {
    if (view.value !== 'menu') return
    const offset = 130   // header (64) + sticky category bar (~50) + a little
    let current = null
    for (const c of navCats.value) {
        const el = document.getElementById(c.id)
        if (el && el.getBoundingClientRect().top - offset <= 1) current = c.id
    }
    if (current && current !== activeCat.value) activeCat.value = current
}

// Keep the active chip in view in the mobile category bar.
watch(activeCat, (id) => {
    document.querySelector(`[data-chip="${id}"]`)?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' })
})

onMounted(async () => {
    syncDir()
    window.addEventListener('scroll', onScroll, { passive: true })
    try {
        const res = await fetchMenu(slug)
        if (res.available === false) unavailable.value = true
        else { payload.value = res.data; document.title = L(res.data.restaurant) || 'Menu' }
    } catch { error.value = true } finally { loading.value = false }
})
function syncDir() {
    document.documentElement.lang = locale.value
    document.documentElement.dir = isAr.value ? 'rtl' : 'ltr'
}
watch(locale, syncDir)
onUnmounted(() => window.removeEventListener('scroll', onScroll))

const navCats = computed(() => {
    const list = []
    if (combos.value.length) list.push({ id: 'offers', label: t('offers') })
    categories.value.forEach(c => list.push({ id: `cat-${c.id}`, label: L(c) }))
    return list
})
function scrollTo(id) {
    activeCat.value = id
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
function goHome() { navDrawer.value = false; view.value = 'menu'; window.scrollTo({ top: 0 }) }
function goBranches() { navDrawer.value = false; view.value = 'branches'; window.scrollTo({ top: 0 }) }

// ---- modal ----
function openModal(kind, ref_) {
    modal.value = { kind, ref: ref_ }
    sel.groups = {}
    qty.value = 1
}
function closeModal() { modal.value = null }
const modalGroups = computed(() => {
    if (!modal.value) return []
    return modal.value.kind === 'item' ? (modal.value.ref.option_groups || []) : (modal.value.ref.groups || [])
})
const groupOptions = (g) => (modal.value.kind === 'item' ? g.options : g.items) || []
function isSelected(gi, oi) {
    const s = sel.groups[gi]
    return Array.isArray(s) ? s.includes(oi) : s === oi
}
function toggleOption(gi, oi, group) {
    const max = group.max_select || 1
    if (max === 1) { sel.groups[gi] = sel.groups[gi] === oi ? undefined : oi; return }
    const arr = Array.isArray(sel.groups[gi]) ? [...sel.groups[gi]] : []
    const at = arr.indexOf(oi)
    if (at >= 0) arr.splice(at, 1)
    else if (arr.length < max) arr.push(oi)
    sel.groups[gi] = arr
}
function selectedIdxs(gi) {
    const s = sel.groups[gi]
    return Array.isArray(s) ? s : (s == null ? [] : [s])
}
// required: item groups flagged required; combo groups always need ≥1
const modalValid = computed(() => {
    return modalGroups.value.every((g, gi) => {
        const need = modal.value.kind === 'combo' ? true : !!g.is_required
        return need ? selectedIdxs(gi).length >= 1 : true
    })
})
function priceOf(kind, ref_, groups) {
    let base = kind === 'item' ? Number(ref_.discounted_price ?? ref_.price) : Number(ref_.base_price)
    const gs = kind === 'item' ? ref_.option_groups : ref_.groups
    ;(gs || []).forEach((g, gi) => {
        const idxs = Array.isArray(groups[gi]) ? groups[gi] : (groups[gi] == null ? [] : [groups[gi]])
        const opts = kind === 'item' ? g.options : g.items
        idxs.forEach(oi => { base += Number((kind === 'item' ? opts[oi]?.price : opts[oi]?.extra_price) || 0) })
    })
    return base
}
const modalUnit = computed(() => modal.value ? priceOf(modal.value.kind, modal.value.ref, sel.groups) : 0)

function addToCart() {
    if (!modalValid.value) return
    const groups = JSON.parse(JSON.stringify(sel.groups))
    const sig = `${modal.value.kind}:${modal.value.ref.id}:${JSON.stringify(groups)}`
    const existing = cart.value.find(l => l.sig === sig)
    if (existing) existing.qty += qty.value
    else cart.value.push({ uid: Date.now() + Math.random(), sig, kind: modal.value.kind, ref: modal.value.ref, groups, qty: qty.value })
    closeModal()
}

// ---- cart helpers ----
function lineOptions(line) {
    const out = []
    const gs = line.kind === 'item' ? line.ref.option_groups : line.ref.groups
    ;(gs || []).forEach((g, gi) => {
        const idxs = Array.isArray(line.groups[gi]) ? line.groups[gi] : (line.groups[gi] == null ? [] : [line.groups[gi]])
        const opts = line.kind === 'item' ? g.options : g.items
        idxs.forEach(oi => { if (opts[oi]) out.push(L(opts[oi])) })
    })
    return out
}
const lineUnit = (line) => priceOf(line.kind, line.ref, line.groups)
const lineTotal = (line) => lineUnit(line) * line.qty
const cartTotal = computed(() => cart.value.reduce((s, l) => s + lineTotal(l), 0))
const cartCount = computed(() => cart.value.reduce((s, l) => s + l.qty, 0))
function bumpLine(line, d) { line.qty = Math.max(1, line.qty + d) }
function removeLine(line) { cart.value = cart.value.filter(l => l.uid !== line.uid) }

// Customer details attached to the order. Phone is required so the restaurant
// can reach the customer; name/address/note are optional (pickup vs delivery).
const customer = reactive({ name: '', phone: '', address: '', note: '' })
const canOrder = computed(() => cart.value.length > 0 && !!waDigits.value && customer.phone.trim().length > 0)

function orderViaWhatsApp() {
    if (!canOrder.value) return
    const lines = cart.value.map(l => {
        const opts = lineOptions(l)
        const optTxt = opts.length ? ` (${opts.join('، ')})` : ''
        return `• ${l.qty}× ${L(l.ref)}${optTxt} — ${money(lineTotal(l))}`
    })
    const details = []
    if (customer.name.trim()) details.push(`${t('f_name')}: ${customer.name.trim()}`)
    details.push(`${t('f_phone')}: ${customer.phone.trim()}`)
    if (customer.address.trim()) details.push(`${t('f_address')}: ${customer.address.trim()}`)
    if (customer.note.trim()) details.push(`${t('f_note')}: ${customer.note.trim()}`)
    const msg = [
        `*${t('new_order')} — ${L(restaurant.value)}*`,
        '',
        ...lines,
        '',
        `*${t('total')}: ${money(cartTotal.value)}*`,
        '',
        ...details,
    ].join('\n')
    window.open(`https://wa.me/${waDigits.value}?text=${encodeURIComponent(msg)}`, '_blank')
}
function toggleLang() { locale.value = isAr.value ? 'en' : 'ar' }
</script>

<template>
    <div :style="{ '--acc': accent }" class="min-h-full pb-20 lg:pb-0">
        <div v-if="loading" class="min-h-screen grid place-items-center">
            <div class="h-10 w-10 rounded-full border-4 border-black/10" :style="{ borderTopColor: accent }" style="animation: spin .8s linear infinite"></div>
        </div>
        <div v-else-if="error || unavailable" class="min-h-screen grid place-items-center text-center px-6">
            <p class="text-lg text-stone-500">{{ unavailable ? t('unavailable') : 'Something went wrong.' }}</p>
        </div>

        <template v-else>
            <!-- Header (original clean style) -->
            <header class="sticky top-0 z-30 backdrop-blur border-b border-stone-200/70" style="background:rgba(250,243,230,.9)">
                <div class="max-w-6xl mx-auto flex items-center justify-between gap-3 px-4 h-16">
                    <div class="flex items-center gap-3 min-w-0">
                        <button class="grid place-items-center h-10 w-10 rounded-xl hover:bg-black/5 text-2xl flex-shrink-0" :style="{ color: accent }" aria-label="menu" @click="navDrawer = true">☰</button>
                        <img v-if="restaurant.logo_url" :src="restaurant.logo_url" class="h-11 w-11 rounded-xl object-cover" :alt="L(restaurant)" />
                        <div v-else class="h-11 w-11 rounded-xl grid place-items-center text-white font-extrabold" :style="{ background: accent }">{{ initial }}</div>
                        <div class="min-w-0">
                            <div class="font-extrabold text-lg leading-tight truncate" style="color:#2a2118">{{ L(restaurant) }}</div>
                            <div v-if="altName" class="text-xs text-stone-400 truncate" :dir="isAr ? 'ltr' : 'rtl'">{{ altName }}</div>
                        </div>
                    </div>
                    <div class="flex items-center gap-2">
                        <button v-if="orderingEnabled" class="lg:hidden relative grid place-items-center h-9 w-9 rounded-lg hover:bg-black/5" :style="{ color: accent }" aria-label="cart" @click="cartDrawer = true">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" class="w-6 h-6"><path d="m5 11 4-7"/><path d="m19 11-4-7"/><path d="M2 11h20"/><path d="m3.5 11 1.6 7.4a2 2 0 0 0 2 1.6h9.8a2 2 0 0 0 2-1.6l1.6-7.4"/><path d="m9 11 1 9"/><path d="M4.5 15.5h15"/><path d="m15 11-1 9"/></svg>
                            <span v-if="cartCount" class="absolute -top-1 -end-1 text-white text-[10px] font-bold rounded-full h-4 min-w-[16px] px-1 grid place-items-center" :style="{ background: accent }">{{ cartCount }}</span>
                        </button>
                        <div class="flex rounded-full border border-stone-200 overflow-hidden text-sm font-bold bg-white">
                            <button class="px-3 py-1.5" :style="isAr ? { background: accent, color: '#fff' } : { color: '#8a7c68' }" @click="locale = 'ar'">ع</button>
                            <button class="px-3 py-1.5" :style="!isAr ? { background: accent, color: '#fff' } : { color: '#8a7c68' }" @click="locale = 'en'">EN</button>
                        </div>
                        <a v-if="waDigits" :href="`https://wa.me/${waDigits}`" target="_blank" rel="noopener"
                            class="hidden sm:flex items-center gap-1.5 bg-green-600 hover:bg-green-700 text-white rounded-lg px-3 h-9 text-sm font-semibold">
                            <svg viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4"><path d="M19.05 4.91A9.82 9.82 0 0 0 12.04 2c-5.46 0-9.91 4.45-9.91 9.91 0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38c1.45.79 3.08 1.21 4.74 1.21h.004c5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01zM12.04 20.15h-.003a8.2 8.2 0 0 1-4.18-1.15l-.3-.18-3.11.82.83-3.04-.2-.31a8.18 8.18 0 0 1-1.26-4.38c0-4.54 3.7-8.24 8.25-8.24 2.2 0 4.27.86 5.83 2.42a8.2 8.2 0 0 1 2.41 5.83c0 4.54-3.7 8.24-8.24 8.24zm4.52-6.16c-.25-.12-1.47-.72-1.69-.81-.23-.08-.39-.12-.56.12-.16.25-.64.81-.79.97-.14.17-.29.19-.54.06-.25-.12-1.05-.39-1.99-1.23-.74-.66-1.23-1.47-1.38-1.72-.14-.25-.01-.38.11-.5.11-.11.25-.29.37-.43.12-.14.16-.25.25-.41.08-.17.04-.31-.02-.43-.06-.12-.56-1.34-.76-1.84-.2-.48-.41-.42-.56-.43-.14-.01-.31-.01-.48-.01a.92.92 0 0 0-.66.31c-.23.25-.87.85-.87 2.07 0 1.22.89 2.4 1.01 2.56.12.17 1.75 2.67 4.23 3.74.59.26 1.05.41 1.41.52.59.19 1.13.16 1.56.1.48-.07 1.47-.6 1.67-1.18.21-.58.21-1.07.14-1.18-.06-.11-.22-.17-.47-.29z"/></svg>
                            WhatsApp</a>
                    </div>
                </div>
            </header>

            <!-- Mobile category bar -->
            <div v-if="view === 'menu' && navCats.length" class="lg:hidden sticky top-16 z-20 border-b border-stone-200/70" style="background:rgba(250,243,230,.95);backdrop-filter:blur(8px)">
                <div class="flex gap-2 overflow-x-auto no-sb px-4 py-2.5">
                    <button v-for="c in navCats" :key="c.id" :data-chip="c.id"
                        class="whitespace-nowrap px-3.5 py-1.5 rounded-full text-sm font-semibold border transition"
                        :class="activeCat === c.id ? 'text-white border-transparent' : 'bg-white text-stone-600 border-stone-200'"
                        :style="activeCat === c.id ? { background: accent } : {}"
                        @click="scrollTo(c.id)">{{ c.label }}</button>
                </div>
            </div>

            <div v-if="view === 'menu'" class="max-w-6xl mx-auto px-4 py-6">
                <div class="menu-grid">
                    <!-- Category sidebar (right in RTL) -->
                    <aside class="hidden lg:block sticky top-20 bg-white rounded-2xl border border-stone-200/70 p-2" style="order:1">
                        <button v-for="c in navCats" :key="c.id"
                            class="w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-xl text-sm font-semibold transition"
                            :class="activeCat === c.id ? 'text-white' : 'hover:bg-stone-50 text-stone-700'"
                            :style="activeCat === c.id ? { background: accent } : {}"
                            @click="scrollTo(c.id)">
                            <span>{{ c.label }}</span><span class="opacity-50">›</span>
                        </button>
                    </aside>

                    <!-- Center -->
                    <main class="min-w-0" style="order:2">
                        <section v-if="combos.length" id="offers" class="mb-8 scroll-mt-32">
                            <h2 class="text-xl font-extrabold mb-3">{{ t('offers') }}</h2>
                            <div class="space-y-3">
                                <button v-for="c in combos" :key="c.id" class="w-full text-start bg-white rounded-2xl border border-stone-200/70 p-3 flex gap-3 items-center hover:shadow-sm transition" @click="openModal('combo', c)">
                                    <img v-if="c.image_url" :src="c.image_url" class="h-20 w-20 rounded-xl object-cover flex-shrink-0" :alt="L(c)" />
                                    <div v-else class="h-20 w-20 rounded-xl flex-shrink-0 grid place-items-center text-2xl" :style="{ background: accent + '22', color: accent }">★</div>
                                    <div class="flex-1 min-w-0">
                                        <div class="font-bold">{{ L(c) }}</div>
                                        <div v-if="L(c, 'description')" class="text-sm text-stone-500 truncate">{{ L(c, 'description') }}</div>
                                        <div class="text-sm font-semibold mt-1" :style="{ color: accent }">{{ t('from') }} {{ money(c.base_price) }}</div>
                                    </div>
                                </button>
                            </div>
                        </section>

                        <section v-for="c in categories" :key="c.id" :id="`cat-${c.id}`" class="mb-8 scroll-mt-32">
                            <h2 class="text-xl font-extrabold mb-3">{{ L(c) }}</h2>
                            <div class="grid sm:grid-cols-2 gap-3">
                                <button v-for="it in c.items" :key="it.id"
                                    class="text-start bg-white rounded-2xl border border-stone-200/70 overflow-hidden hover:shadow-sm transition flex flex-col"
                                    :class="{ 'opacity-60': !it.is_available }"
                                    :disabled="!it.is_available"
                                    @click="openModal('item', it)">
                                    <div v-if="it.image_url" class="h-36 w-full overflow-hidden"><img :src="it.image_url" class="h-full w-full object-cover" :class="{ grayscale: !it.is_available }" :alt="L(it)" /></div>
                                    <div class="p-3 flex-1">
                                        <div class="flex items-start justify-between gap-2">
                                            <div class="font-bold">{{ L(it) }}</div>
                                            <div class="font-bold whitespace-nowrap" :style="{ color: accent }">{{ money(it.discounted_price ?? it.price) }}</div>
                                        </div>
                                        <p v-if="L(it, 'description')" class="text-sm text-stone-500 mt-1 line-clamp-2">{{ L(it, 'description') }}</p>
                                    </div>
                                </button>
                            </div>
                        </section>

                    </main>

                    <!-- Cart sidebar (left in RTL) -->
                    <aside v-if="orderingEnabled" class="hidden lg:block sticky top-20 bg-white rounded-2xl border border-stone-200/70 p-4" style="order:3">
                        <h3 class="font-bold mb-3">{{ t('cart') }} <span v-if="cartCount" class="text-sm font-normal text-stone-400">({{ cartCount }})</span></h3>
                        <div v-if="!cart.length" class="text-center py-10 text-stone-400">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="w-12 h-12 mx-auto mb-3 text-stone-300"><path d="m5 11 4-7"/><path d="m19 11-4-7"/><path d="M2 11h20"/><path d="m3.5 11 1.6 7.4a2 2 0 0 0 2 1.6h9.8a2 2 0 0 0 2-1.6l1.6-7.4"/><path d="m9 11 1 9"/><path d="M4.5 15.5h15"/><path d="m15 11-1 9"/></svg><p class="text-sm">{{ t('cart_empty') }}</p>
                        </div>
                        <template v-else>
                            <div class="space-y-3 max-h-[50vh] overflow-y-auto -mx-1 px-1">
                                <div v-for="line in cart" :key="line.uid" class="border-b border-stone-100 pb-3">
                                    <div class="flex justify-between gap-2">
                                        <div class="font-semibold text-sm">{{ L(line.ref) }}</div>
                                        <button class="text-stone-300 hover:text-red-500 text-xs" @click="removeLine(line)">✕</button>
                                    </div>
                                    <div v-if="lineOptions(line).length" class="text-xs text-stone-400 mt-0.5">{{ lineOptions(line).join('، ') }}</div>
                                    <div class="flex items-center justify-between mt-2">
                                        <div class="flex items-center gap-2 border border-stone-200 rounded-lg px-1">
                                            <button class="h-6 w-6 text-stone-500" @click="bumpLine(line, -1)">−</button>
                                            <span class="text-sm font-bold w-4 text-center">{{ line.qty }}</span>
                                            <button class="h-6 w-6 text-stone-500" @click="bumpLine(line, 1)">+</button>
                                        </div>
                                        <span class="text-sm font-bold" :style="{ color: accent }">{{ money(lineTotal(line)) }}</span>
                                    </div>
                                </div>
                            </div>
                            <div class="flex justify-between items-center mt-4 font-bold">
                                <span>{{ t('total') }}</span><span :style="{ color: accent }">{{ money(cartTotal) }}</span>
                            </div>
                            <div class="mt-4 pt-3 border-t border-stone-100 space-y-2">
                                <p class="text-sm font-bold text-stone-600">{{ t('your_details') }}</p>
                                <input v-model="customer.name" type="text" :placeholder="t('f_name')" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm focus:outline-none focus:border-stone-400" />
                                <input v-model="customer.phone" type="tel" dir="ltr" :placeholder="t('f_phone') + ' *'" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm text-start focus:outline-none focus:border-stone-400" />
                                <input v-model="customer.address" type="text" :placeholder="t('f_address')" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm focus:outline-none focus:border-stone-400" />
                                <textarea v-model="customer.note" rows="2" :placeholder="t('f_note')" class="w-full rounded-lg border border-stone-200 px-3 py-2 text-sm resize-none focus:outline-none focus:border-stone-400"></textarea>
                            </div>
                            <button class="w-full mt-3 h-11 rounded-xl bg-green-600 hover:bg-green-700 text-white font-bold flex items-center justify-center gap-2 disabled:opacity-50"
                                :disabled="!canOrder" @click="orderViaWhatsApp">
                                <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path d="M19.05 4.91A9.82 9.82 0 0 0 12.04 2c-5.46 0-9.91 4.45-9.91 9.91 0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38c1.45.79 3.08 1.21 4.74 1.21h.004c5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01zM12.04 20.15h-.003a8.2 8.2 0 0 1-4.18-1.15l-.3-.18-3.11.82.83-3.04-.2-.31a8.18 8.18 0 0 1-1.26-4.38c0-4.54 3.7-8.24 8.25-8.24 2.2 0 4.27.86 5.83 2.42a8.2 8.2 0 0 1 2.41 5.83c0 4.54-3.7 8.24-8.24 8.24zm4.52-6.16c-.25-.12-1.47-.72-1.69-.81-.23-.08-.39-.12-.56.12-.16.25-.64.81-.79.97-.14.17-.29.19-.54.06-.25-.12-1.05-.39-1.99-1.23-.74-.66-1.23-1.47-1.38-1.72-.14-.25-.01-.38.11-.5.11-.11.25-.29.37-.43.12-.14.16-.25.25-.41.08-.17.04-.31-.02-.43-.06-.12-.56-1.34-.76-1.84-.2-.48-.41-.42-.56-.43-.14-.01-.31-.01-.48-.01a.92.92 0 0 0-.66.31c-.23.25-.87.85-.87 2.07 0 1.22.89 2.4 1.01 2.56.12.17 1.75 2.67 4.23 3.74.59.26 1.05.41 1.41.52.59.19 1.13.16 1.56.1.48-.07 1.47-.6 1.67-1.18.21-.58.21-1.07.14-1.18-.06-.11-.22-.17-.47-.29z"/></svg>
                                {{ t('order_wa') }}</button>
                        </template>
                    </aside>
                </div>
            </div>

            <!-- Branches page -->
            <main v-else-if="view === 'branches'" class="max-w-3xl mx-auto px-4 py-8">
                <button class="font-semibold mb-5" :style="{ color: accent }" @click="goHome">‹ {{ t('home') }}</button>
                <h1 class="text-2xl font-extrabold mb-5">{{ t('branches') }}</h1>
                <div class="space-y-3">
                    <div v-for="b in branches" :key="b.id" class="bg-white rounded-2xl border border-stone-200/70 p-5">
                        <div class="flex items-start justify-between gap-2">
                            <div class="font-bold text-lg">{{ L(b) }}</div>
                            <span class="text-xs font-semibold px-2.5 py-1 rounded-full whitespace-nowrap" :class="b.is_open ? 'bg-green-100 text-green-700' : 'bg-stone-100 text-stone-500'">{{ b.is_open ? t('open') : t('closed') }}</span>
                        </div>
                        <div v-if="b.address" class="text-sm text-stone-500 mt-1">{{ b.address }}</div>
                        <div v-if="b.opening_hours" class="text-sm text-stone-500 mt-1">🕒 {{ b.opening_hours }}</div>
                        <div class="flex flex-wrap gap-2 mt-3">
                            <a v-if="b.map_url" :href="b.map_url" target="_blank" rel="noopener" class="text-sm font-semibold px-3 py-1.5 rounded-lg border border-stone-200" :style="{ color: accent }">📍 {{ t('location') }}</a>
                            <a v-if="b.phone" :href="`tel:${b.phone}`" dir="ltr" class="text-sm font-semibold px-3 py-1.5 rounded-lg border border-stone-200" :style="{ color: accent }">✆ {{ b.phone }}</a>
                        </div>
                    </div>
                </div>
            </main>

            <!-- Item / Combo modal -->
            <div v-if="modal" class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
                <div class="absolute inset-0 bg-black/50" @click="closeModal"></div>
                <div class="relative bg-white w-full sm:max-w-md sm:rounded-3xl rounded-t-3xl max-h-[92vh] overflow-y-auto shadow-2xl">
                    <div class="relative h-44 bg-stone-100">
                        <img v-if="modal.ref.image_url" :src="modal.ref.image_url" class="h-full w-full object-cover" />
                        <button class="absolute top-3 start-3 h-9 w-9 rounded-full bg-white/90 grid place-items-center text-xl" @click="closeModal">×</button>
                    </div>
                    <div class="p-5">
                        <h3 class="text-xl font-extrabold">{{ L(modal.ref) }}</h3>
                        <p v-if="L(modal.ref, 'description')" class="text-stone-500 mt-1">{{ L(modal.ref, 'description') }}</p>
                        <p v-if="modal.kind === 'combo'" class="text-stone-500 mt-1">{{ t('from') }} {{ money(modal.ref.base_price) }}</p>

                        <div v-for="(g, gi) in modalGroups" :key="gi" class="mt-5">
                            <div class="flex items-center gap-2 mb-1">
                                <span class="font-bold">{{ L(g) }}</span>
                                <span v-if="modal.kind === 'item' && g.is_required" class="text-xs font-semibold px-2 py-0.5 rounded-full bg-green-100 text-green-700">{{ t('required') }}</span>
                                <span class="ms-auto text-xs text-stone-400">{{ t('choose') }} {{ g.max_select }}</span>
                            </div>
                            <label v-for="(o, oi) in groupOptions(g)" :key="oi" class="flex items-center gap-3 py-3 border-t border-stone-100 cursor-pointer" @click="toggleOption(gi, oi, g)">
                                <span class="h-5 w-5 border-2 flex-shrink-0 grid place-items-center"
                                    :class="(g.max_select || 1) > 1 ? 'rounded-md' : 'rounded-full'"
                                    :style="{ borderColor: accent, background: isSelected(gi, oi) ? accent : 'transparent' }">
                                    <span v-if="isSelected(gi, oi)" class="text-white text-xs">✓</span>
                                </span>
                                <span class="flex-1">{{ L(o) }}</span>
                                <span v-if="Number(o.price || o.extra_price) > 0" class="font-semibold" :style="{ color: accent }">+{{ money(o.price || o.extra_price) }}</span>
                            </label>
                        </div>
                    </div>
                    <div v-if="orderingEnabled" class="sticky bottom-0 bg-white border-t border-stone-100 p-4 flex items-center gap-3">
                        <div class="flex items-center gap-3 border border-stone-200 rounded-xl px-2 py-1">
                            <button class="h-8 w-8 grid place-items-center text-lg" @click="qty = Math.max(1, qty - 1)">−</button>
                            <span class="w-5 text-center font-bold">{{ qty }}</span>
                            <button class="h-8 w-8 grid place-items-center text-lg" @click="qty++">+</button>
                        </div>
                        <button class="flex-1 h-12 rounded-xl text-white font-bold disabled:opacity-50" :style="{ background: accent }" :disabled="!modalValid" @click="addToCart">
                            {{ t('add') }} ({{ money(modalUnit * qty) }})
                        </button>
                    </div>
                </div>
            </div>

            <!-- Mobile cart bar + drawer -->
            <button v-if="orderingEnabled && cartCount && !cartDrawer" class="lg:hidden fixed bottom-0 inset-x-0 z-40 m-3 h-13 rounded-2xl text-white font-bold flex items-center justify-between px-5 shadow-lg" style="height:52px" :style="{ background: accent }" @click="cartDrawer = true">
                <span>{{ t('view_cart') }} ({{ cartCount }})</span><span>{{ money(cartTotal) }}</span>
            </button>
            <div v-if="orderingEnabled && cartDrawer" class="lg:hidden fixed inset-0 z-50">
                <div class="absolute inset-0 bg-black/40" @click="cartDrawer = false"></div>
                <div class="absolute bottom-0 inset-x-0 bg-white rounded-t-3xl max-h-[85vh] overflow-y-auto p-5">
                    <div class="flex items-center justify-between mb-4">
                        <h3 class="font-bold">{{ t('cart') }}</h3>
                        <button class="text-xl text-stone-400" @click="cartDrawer = false">×</button>
                    </div>
                    <div v-if="!cart.length" class="text-center py-10 text-stone-400"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="w-12 h-12 mx-auto mb-3 text-stone-300"><path d="m5 11 4-7"/><path d="m19 11-4-7"/><path d="M2 11h20"/><path d="m3.5 11 1.6 7.4a2 2 0 0 0 2 1.6h9.8a2 2 0 0 0 2-1.6l1.6-7.4"/><path d="m9 11 1 9"/><path d="M4.5 15.5h15"/><path d="m15 11-1 9"/></svg><p class="text-sm">{{ t('cart_empty') }}</p></div>
                    <template v-else>
                        <div v-for="line in cart" :key="line.uid" class="border-b border-stone-100 pb-3 mb-3">
                            <div class="flex justify-between gap-2"><div class="font-semibold text-sm">{{ L(line.ref) }}</div><button class="text-stone-300 text-xs" @click="removeLine(line)">✕</button></div>
                            <div v-if="lineOptions(line).length" class="text-xs text-stone-400 mt-0.5">{{ lineOptions(line).join('، ') }}</div>
                            <div class="flex items-center justify-between mt-2">
                                <div class="flex items-center gap-2 border border-stone-200 rounded-lg px-1">
                                    <button class="h-6 w-6 text-stone-500" @click="bumpLine(line, -1)">−</button>
                                    <span class="text-sm font-bold w-4 text-center">{{ line.qty }}</span>
                                    <button class="h-6 w-6 text-stone-500" @click="bumpLine(line, 1)">+</button>
                                </div>
                                <span class="text-sm font-bold" :style="{ color: accent }">{{ money(lineTotal(line)) }}</span>
                            </div>
                        </div>
                        <div class="flex justify-between items-center font-bold"><span>{{ t('total') }}</span><span :style="{ color: accent }">{{ money(cartTotal) }}</span></div>
                        <div class="mt-4 pt-3 border-t border-stone-100 space-y-2">
                            <p class="text-sm font-bold text-stone-600">{{ t('your_details') }}</p>
                            <input v-model="customer.name" type="text" :placeholder="t('f_name')" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm focus:outline-none focus:border-stone-400" />
                            <input v-model="customer.phone" type="tel" dir="ltr" :placeholder="t('f_phone') + ' *'" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm text-start focus:outline-none focus:border-stone-400" />
                            <input v-model="customer.address" type="text" :placeholder="t('f_address')" class="w-full h-10 rounded-lg border border-stone-200 px-3 text-sm focus:outline-none focus:border-stone-400" />
                            <textarea v-model="customer.note" rows="2" :placeholder="t('f_note')" class="w-full rounded-lg border border-stone-200 px-3 py-2 text-sm resize-none focus:outline-none focus:border-stone-400"></textarea>
                        </div>
                        <button class="w-full mt-3 h-12 rounded-xl bg-green-600 text-white font-bold flex items-center justify-center gap-2 disabled:opacity-50" :disabled="!canOrder" @click="orderViaWhatsApp">
                            <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path d="M19.05 4.91A9.82 9.82 0 0 0 12.04 2c-5.46 0-9.91 4.45-9.91 9.91 0 1.75.46 3.45 1.32 4.95L2.05 22l5.25-1.38c1.45.79 3.08 1.21 4.74 1.21h.004c5.46 0 9.91-4.45 9.91-9.91 0-2.65-1.03-5.14-2.9-7.01zM12.04 20.15h-.003a8.2 8.2 0 0 1-4.18-1.15l-.3-.18-3.11.82.83-3.04-.2-.31a8.18 8.18 0 0 1-1.26-4.38c0-4.54 3.7-8.24 8.25-8.24 2.2 0 4.27.86 5.83 2.42a8.2 8.2 0 0 1 2.41 5.83c0 4.54-3.7 8.24-8.24 8.24zm4.52-6.16c-.25-.12-1.47-.72-1.69-.81-.23-.08-.39-.12-.56.12-.16.25-.64.81-.79.97-.14.17-.29.19-.54.06-.25-.12-1.05-.39-1.99-1.23-.74-.66-1.23-1.47-1.38-1.72-.14-.25-.01-.38.11-.5.11-.11.25-.29.37-.43.12-.14.16-.25.25-.41.08-.17.04-.31-.02-.43-.06-.12-.56-1.34-.76-1.84-.2-.48-.41-.42-.56-.43-.14-.01-.31-.01-.48-.01a.92.92 0 0 0-.66.31c-.23.25-.87.85-.87 2.07 0 1.22.89 2.4 1.01 2.56.12.17 1.75 2.67 4.23 3.74.59.26 1.05.41 1.41.52.59.19 1.13.16 1.56.1.48-.07 1.47-.6 1.67-1.18.21-.58.21-1.07.14-1.18-.06-.11-.22-.17-.47-.29z"/></svg>
                            {{ t('order_wa') }}</button>
                    </template>
                </div>
            </div>
            <!-- Side menu (opens from the start side: right in AR, left in EN) -->
            <div v-if="navDrawer" class="fixed inset-0 z-50">
                <div class="absolute inset-0 bg-black/40" @click="navDrawer = false"></div>
                <nav class="absolute start-0 top-0 h-full w-72 max-w-[80%] bg-white shadow-xl flex flex-col">
                    <div class="flex items-center justify-end h-14 px-4 border-b border-stone-100">
                        <button class="text-2xl text-stone-400 leading-none" @click="navDrawer = false">×</button>
                    </div>
                    <button class="text-start px-5 py-4 border-b border-stone-100 font-semibold hover:bg-stone-50" @click="goHome">{{ t('home') }}</button>
                    <button v-if="branches.length" class="text-start px-5 py-4 border-b border-stone-100 font-semibold hover:bg-stone-50" @click="goBranches">{{ t('branches') }}</button>
                </nav>
            </div>
        </template>
    </div>
</template>

<style>
@keyframes spin { to { transform: rotate(360deg); } }
.line-clamp-2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
</style>
