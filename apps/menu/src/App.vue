<script setup>
import { ref, computed, reactive, watch, onMounted, onUnmounted } from 'vue'
import { postOrder } from './api.js'
import { track } from './lib/analytics.js'
import { useLocale } from './composables/useLocale'
import { useCart } from './composables/useCart'
import { useOrder } from './composables/useOrder'
import { useMenu } from './composables/useMenu'
import { useUserInfo } from './composables/useUserInfo'
import { useTableSession } from './composables/useTableSession'
import Header from './components/Header.vue'
import Hero from './components/Hero.vue'
import CategoryTabs from './components/CategoryTabs.vue'
import MenuGrid from './components/MenuGrid.vue'
import MenuSkeleton from './components/MenuSkeleton.vue'
import Footer from './components/Footer.vue'
import BranchesPage from './components/BranchesPage.vue'
import CartDrawer from './components/CartDrawer.vue'
import ItemModal from './components/ItemModal.vue'
import OrderSuccessModal from './components/OrderSuccessModal.vue'
import UserInfoDialog from './components/UserInfoDialog.vue'
import SideMenu from './components/SideMenu.vue'

// Slug normally comes from the subdomain (e.g. acme.xorder.io → "acme").
// On a bare host (localhost / IP) there is no subdomain, so fall back to a
// ?r=<slug> query param for local development.
const sub = window.location.hostname.split('.')[0]
const bareHost = sub === 'localhost' || /^\d+$/.test(sub)
const slug = (bareHost && new URLSearchParams(window.location.search).get('r')) || sub

const { locale, isAr, t, localize } = useLocale('ar')
// A table QR scan (…/t/{token}) binds this visit to a physical table.
const { hasTable, sessionToken, tableLabel, area: tableArea, tableError } = useTableSession(locale.value)
const tableAreaName = computed(() => {
    const a = tableArea.value
    if (!a) return ''
    return isAr.value ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar)
})
const { cart, cartCount, cartTotal, addToCart, removeLine, bumpLine, clearCart, getLineOptions, calculateLinePrice } = useCart(slug)
const { submittingOrder, orderSuccess, lastOrderUrl, lastOrderCode, customer, buildOrderData, sendToWhatsApp } = useOrder()
const { userInfoDialog, isEditing, userInfo, editForm, saveSuccess, hasUserInfo, initials, loadUserInfo, saveUserInfo, enterEditMode, cancelEdit, clearUserInfo, openDialog, closeDialog } = useUserInfo()

// Hydrate any saved diner info up front so the checkout form can prefill.
loadUserInfo()

const { payload, loading, error, unavailable, activeCat, view, restaurant, categories, combos, branches, navCats, scrollTo, goHome, goBranches } = useMenu(slug)

// Funnel: one menu_viewed event per visit, once the payload actually loads.
let viewTracked = false
watch(payload, (loaded) => {
    if (loaded && !viewTracked) {
        viewTracked = true
        track('menu_viewed', { slug })
    }
})

const navDrawer = ref(false)
const cartDrawer = ref(false)
const searchQuery = ref('')
const modal = ref(null)
const sel = reactive({ groups: {} })
const qty = ref(1)

const hasOverlay = computed(() => Boolean(
    modal.value || cartDrawer.value || navDrawer.value || userInfoDialog.value || orderSuccess.value
))

watch(hasOverlay, (locked) => {
    document.body.style.overflow = locked ? 'hidden' : ''
}, { immediate: true })

function closeTopOverlay(event) {
    if (event.key !== 'Escape') return
    if (modal.value) closeModal()
    else if (cartDrawer.value) cartDrawer.value = false
    else if (navDrawer.value) navDrawer.value = false
    else if (userInfoDialog.value) closeDialog()
    else if (orderSuccess.value) orderSuccess.value = false
}

onMounted(() => window.addEventListener('keydown', closeTopOverlay))
onUnmounted(() => {
    window.removeEventListener('keydown', closeTopOverlay)
    document.body.style.overflow = ''
})

const accent = computed(() => restaurant.value?.brand_color || '#f59e0b')
const sym = computed(() => {
    const r = restaurant.value
    // Egypt: EGP in English, ج٫م in Arabic; other currencies keep the API symbol.
    if (r?.currency === 'EGP') return isAr.value ? 'ج٫م' : 'EGP'
    return r?.currency_symbol || r?.currency || ''
})
const waDigits = computed(() => (restaurant.value?.whatsapp_number || '').replace(/[^0-9]/g, ''))
const orderingEnabled = computed(() => restaurant.value?.ordering_enabled !== false)
const bilingual = computed(() => restaurant.value?.bilingual !== false)
const canOrder = computed(() => cartCount.value > 0 && !!waDigits.value)

// Order type (delivery / pickup / dine-in). Frontend-only: rides along in the
// WhatsApp message so the restaurant knows how the diner wants to receive it.
const orderType = ref('pickup')
const orderTypes = computed(() => [
    { value: 'pickup', label: t('pickup') },
    { value: 'delivery', label: t('delivery') },
])
const orderTypeLabel = computed(() => orderTypes.value.find(o => o.value === orderType.value)?.label || '')

const modalGroups = computed(() => {
    if (!modal.value) return []
    return modal.value.kind === 'item' ? (modal.value.ref.option_groups || []) : (modal.value.ref.groups || [])
})

const modalValid = computed(() => {
    return modalGroups.value.every((g, gi) => {
        const need = modal.value.kind === 'combo' ? true : !!g.is_required
        const selected = Array.isArray(sel.groups[gi]) ? sel.groups[gi] : (sel.groups[gi] == null ? [] : [sel.groups[gi]])
        return need ? selected.length >= 1 : true
    })
})

const modalUnit = computed(() => {
    if (!modal.value) return 0
    return calculateLinePrice(modal.value.kind, modal.value.ref, sel.groups)
})

const money = (v) => {
    const amount = Number(v ?? 0)
    return `${Number.isFinite(amount) ? amount.toFixed(2) : '0.00'} ${sym.value}`
}

function toggleOption(gi, oi, group) {
    const max = group.max_select || 1
    if (max === 1) {
        sel.groups[gi] = sel.groups[gi] === oi ? undefined : oi
        return
    }
    const arr = Array.isArray(sel.groups[gi]) ? [...sel.groups[gi]] : []
    const at = arr.indexOf(oi)
    if (at >= 0) arr.splice(at, 1)
    else if (arr.length < max) arr.push(oi)
    sel.groups[gi] = arr
}

function openModal(kind, ref_) {
    modal.value = { kind, ref: ref_ }
    sel.groups = {}
    qty.value = 1
}

function closeModal() {
    modal.value = null
}

function addToCartHandler(note) {
    if (!modalValid.value) return
    track('menu_add_to_cart', { slug, kind: modal.value.kind })
    addToCart(modal.value.kind, modal.value.ref, sel.groups, qty.value, note)
    // Just add and bump the header count — don't pop the cart dialog open.
    closeModal()
}

function submitOrder(details) {
    // Guard against double-clicks racing the disabled state.
    if (submittingOrder.value || !canOrder.value) return
    submittingOrder.value = true

    // Remember the diner for next time and carry the details on the order.
    Object.assign(editForm, { name: details.name, phone: details.phone, email: details.email, address: details.address })
    saveUserInfo()
    customer.name = details.name
    customer.phone = details.phone
    customer.note = details.note

    const orderData = buildOrderData(cart.value, restaurant.value, cartCount.value, cartTotal.value, money, localize, getLineOptions, orderTypeLabel.value)

    // Durable record first — fire-and-forget: window.open must stay inside
    // the user gesture, so the API call is never awaited. The order code
    // fills into the success dialog when the response lands.
    lastOrderCode.value = ''
    const snapshot = {
        items: cart.value.map(line => ({
            name: localize(line.ref),
            qty: line.qty,
            options: getLineOptions(line, localize),
            note: line.note || null,
            line_total: +(line.qty * line.price).toFixed(2),
        })),
        total: +cartTotal.value.toFixed(2),
        customer_name: details.name || null,
        customer_phone: details.phone || null,
        customer_email: details.email || null,
        customer_address: details.address || null,
        note: details.note || null,
        order_type: orderType.value || null,
        session_token: sessionToken.value || undefined,
    }
    postOrder(slug, snapshot)
        .then(res => { lastOrderCode.value = res?.data?.code || '' })
        .catch(() => { /* WhatsApp handoff still carries the order */ })

    sendToWhatsApp(orderData, waDigits.value, t)
    track('menu_order_submitted', { slug, total: snapshot.total, items: cartCount.value })

    cartDrawer.value = false
    clearCart()
    submittingOrder.value = false
    // Explicit confirmation with a re-open link — popup blockers and missing
    // WhatsApp installs would otherwise swallow the order silently.
    orderSuccess.value = true
}

function updateUserField(field, value) {
    editForm[field] = value
}
</script>

<template>
    <div :style="{ '--accent': accent, '--acc': accent }" class="site-shell">
        <MenuSkeleton v-if="loading" />

        <div v-else-if="error || unavailable" class="min-h-screen grid place-items-center text-center px-6">
            <p class="text-lg text-stone-500">{{ unavailable ? t('unavailable') : t('error_generic') }}</p>
        </div>

        <template v-else>
            <Header
                :restaurant="restaurant"
                :cartCount="cartCount"
                :bilingual="bilingual"
                :isAr="isAr"
                :waDigits="waDigits"
                :orderingEnabled="orderingEnabled"
                :locale="locale"
                :t="t"
                @openCart="cartDrawer = true"
                @changeLocale="locale = $event"
                @openMenu="navDrawer = true"
            />

            <div v-if="hasTable" class="table-banner">
                <span class="table-banner__pin">◈</span>
                <span>{{ isAr ? 'طاولة' : 'Table' }} {{ tableLabel }}<span v-if="tableAreaName"> — {{ tableAreaName }}</span></span>
            </div>
            <div v-else-if="tableError" class="table-banner table-banner--error">{{ tableError }}</div>

            <div class="page-wrap">
                <template v-if="view === 'menu'">
                    <Hero
                        :restaurant="restaurant"
                        :isAr="isAr"
                        :t="t"
                        :localize="localize"
                    />

                    <CategoryTabs
                        :navCats="navCats"
                        :activeCat="activeCat"
                        :search="searchQuery"
                        :t="t"
                        :localize="localize"
                        @selectCategory="scrollTo"
                        @update:search="searchQuery = $event"
                    />

                    <MenuGrid
                        :categories="categories"
                        :combos="combos"
                        :search="searchQuery"
                        :t="t"
                        :money="money"
                        :localize="localize"
                        @openModal="openModal"
                        @activeSection="activeCat = $event"
                    />
                </template>

                <BranchesPage
                    v-else-if="view === 'branches'"
                    :branches="branches"
                    :t="t"
                    :accent="accent"
                    @goHome="goHome(); navDrawer = false"
                />
            </div>

            <Footer :t="t" />

            <CartDrawer
                v-if="orderingEnabled"
                :isOpen="cartDrawer"
                :cart="cart"
                :cartCount="cartCount"
                :cartTotal="cartTotal"
                :canOrder="canOrder"
                :isSubmitting="submittingOrder"
                :orderType="orderType"
                :orderTypes="orderTypes"
                :userInfo="userInfo"
                :t="t"
                :money="money"
                :localize="localize"
                :getLineOptions="getLineOptions"
                @close="cartDrawer = false"
                @removeLine="removeLine"
                @bumpLine="bumpLine"
                @clearCart="clearCart"
                @changeOrderType="orderType = $event"
                @submit="submitOrder"
            />

            <ItemModal
                :isOpen="!!modal"
                :item="modal?.ref"
                :kind="modal?.kind"
                :quantity="qty"
                :selectedGroups="sel.groups"
                :orderingEnabled="orderingEnabled"
                :t="t"
                :money="money"
                :localize="localize"
                :isValid="modalValid"
                :unitPrice="modalUnit"
                @close="closeModal"
                @toggleOption="toggleOption"
                @updateQuantity="qty = $event"
                @addToCart="addToCartHandler"
            />

            <OrderSuccessModal
                :isOpen="orderSuccess"
                :reopenUrl="lastOrderUrl"
                :orderCode="lastOrderCode"
                :t="t"
                @close="orderSuccess = false"
            />

            <SideMenu
                :isOpen="navDrawer"
                :hasBranches="branches.length > 0"
                :waDigits="waDigits"
                :restaurant="restaurant"
                :isAr="isAr"
                :t="t"
                @close="navDrawer = false"
                @goHome="goHome(); navDrawer = false"
                @goBranches="goBranches(); navDrawer = false"
            />

            <UserInfoDialog
                :isOpen="userInfoDialog"
                :isEditing="isEditing"
                :userInfo="userInfo"
                :editForm="editForm"
                :saveSuccess="saveSuccess"
                :hasUserInfo="hasUserInfo"
                :initials="initials"
                :accent="accent"
                :t="t"
                @close="closeDialog"
                @enterEdit="enterEditMode"
                @cancelEdit="cancelEdit"
                @save="saveUserInfo"
                @clear="clearUserInfo"
                @updateField="updateUserField"
            />
        </template>
    </div>
</template>
