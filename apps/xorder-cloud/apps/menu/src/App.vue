<script setup>
import { ref, computed, reactive, watch, onMounted, onUnmounted, defineAsyncComponent } from 'vue'
import { postOrder } from './api.js'
import { track } from './lib/analytics.js'
import { warm } from './lib/prefetch.js'
import { useLocale } from './composables/useLocale'
import { useCart } from './composables/useCart'
import { useOrder } from './composables/useOrder'
import { useMenu } from './composables/useMenu'
import { useStickyLayout } from './composables/useStickyLayout'
import { useUserInfo } from './composables/useUserInfo'
import { useTableSession } from './composables/useTableSession'
import { useReviewPrompt } from './composables/useReviewPrompt'
import Header from './components/Header.vue'
import Hero from './components/Hero.vue'
import CategoryTabs from './components/CategoryTabs.vue'
import MenuGrid from './components/MenuGrid.vue'
import MenuSkeleton from './components/MenuSkeleton.vue'
import Footer from './components/Footer.vue'

// The first screen is the topbar, the category toolbar and the menu grid —
// everything above stays in the entry bundle. Everything below only exists
// behind a tap (a modal, a drawer, the branches page) or behind a table QR
// scan, so it is code-split: a QR scan is almost always a cold load on mobile
// data, and shipping the checkout flow to a diner who is still reading the
// menu costs them download and parse time before they see a single item.
// The checkout components in particular drag in libphonenumber's metadata,
// which is a third of the bundle on its own.
//
// Each loader is kept alongside its component so it can be warmed (see the
// `warm` calls below) the moment a diner shows intent, rather than on the tap.
const loadItemModal = () => import('./components/ItemModal.vue')
const loadCartDrawer = () => import('./components/CartDrawer.vue')
const loadOrderSuccess = () => import('./components/OrderSuccessModal.vue')
const ItemModal = defineAsyncComponent(loadItemModal)
const CartDrawer = defineAsyncComponent(loadCartDrawer)
const OrderSuccessModal = defineAsyncComponent(loadOrderSuccess)
const RestaurantInfoModal = defineAsyncComponent(() => import('./components/RestaurantInfoModal.vue'))
const BranchesPage = defineAsyncComponent(() => import('./components/BranchesPage.vue'))
const UserInfoDialog = defineAsyncComponent(() => import('./components/UserInfoDialog.vue'))
const SideMenu = defineAsyncComponent(() => import('./components/SideMenu.vue'))
const BillRequestButton = defineAsyncComponent(() => import('./components/BillRequestButton.vue'))
const ReviewPromptModal = defineAsyncComponent(() => import('./components/ReviewPromptModal.vue'))

// Slug normally comes from the subdomain (e.g. acme.xorder.io → "acme").
// On a bare host (localhost / IP) there is no subdomain, so fall back to a
// ?r=<slug> query param for local development.
const sub = window.location.hostname.split('.')[0]
const bareHost = sub === 'localhost' || /^\d+$/.test(sub)
const slug = (bareHost && new URLSearchParams(window.location.search).get('r')) || sub

const { locale, isAr, t, localize } = useLocale('ar')
// A table QR scan (…/t/{token}) binds this visit to a physical table.
const { hasTable, sessionToken, tableLabel, area: tableArea, billRequests, internalReviews, tableError, locating, orderingBlocked, canRetryLocation, retry: retryTable } = useTableSession(locale.value, t)
const tableAreaName = computed(() => {
    const a = tableArea.value
    if (!a) return ''
    return isAr.value ? (a.name_ar || a.name_en) : (a.name_en || a.name_ar)
})
const { cart, cartCount, cartTotal, addToCart, removeLine, bumpLine, clearCart, getLineOptions, getLineVariant, getLineExtras, getLineOptionIds, calculateLinePrice } = useCart(slug)
const { submittingOrder, orderSuccess, lastOrderUrl, lastOrderCode, lastOrderId, customer, buildOrderData, sendToWhatsApp } = useOrder()
// The server's reason when it refused the order (XORD-047), shown instead of success.
const orderError = ref('')
const { userInfoDialog, isEditing, userInfo, editForm, saveSuccess, hasUserInfo, initials, loadUserInfo, saveUserInfo, enterEditMode, cancelEdit, clearUserInfo, openDialog, closeDialog } = useUserInfo()
const { remember: rememberPendingReview, resolveClosedOrder } = useReviewPrompt(slug)

// Hydrate any saved diner info up front so the checkout form can prefill.
loadUserInfo()

const { payload, loading, error, unavailable, activeCat, spyLocked, view, restaurant, categories, combos, branches, navCats, scrollTo, goHome, goBranches, loadMenu } = useMenu(slug)

// Keep the measured sticky/footer heights (--topbar-h / --stack-h / --footer-h)
// in sync as the payload loads, the view switches, and the table banner shows.
useStickyLayout(() => [loading.value, view.value, hasTable.value, tableError.value])

// Funnel: one menu_viewed event per visit, once the payload actually loads.
let viewTracked = false
watch(payload, (loaded) => {
    if (loaded && !viewTracked) {
        viewTracked = true
        track('menu_viewed', { slug })
        // The grid is on screen and the diner is reading it — the next tap is
        // almost always an item card, so fetch that chunk now instead of on
        // the tap. It is small; the checkout bundle waits for real intent.
        warm(loadItemModal)
    }
})

// A line in the cart is the clearest signal a diner means to check out, so
// that is when the (much heavier, phone-metadata-carrying) checkout chunk is
// worth fetching — along with the confirmation that follows it, because the
// moment right after "send order" is the worst one to leave blank. Immediate,
// because a returning diner can arrive with a restored cart and go straight
// for the cart button.
watch(cartCount, (n) => {
    if (n === 0) return
    warm(loadCartDrawer)
    warm(loadOrderSuccess)
}, { immediate: true })

const navDrawer = ref(false)
const cartDrawer = ref(false)
const infoOpen = ref(false)
const reviewPrompt = ref(false)
const searchQuery = ref('')

// Private post-order feedback is available when the feature is on — from the
// table context at a scanned table, otherwise from the menu payload.
const reviewsEnabled = computed(() => internalReviews.value || restaurant.value?.internal_reviews === true)

// The feedback invite is deferred to the diner's next visit, not shown at
// checkout: once feature state is known, check whether their last system order
// has been closed and, if so, pop the prompt once. Guarded to run a single time.
let reviewReturnChecked = false
watch(reviewsEnabled, async (enabled) => {
    if (!enabled || reviewReturnChecked) return
    reviewReturnChecked = true
    const orderId = await resolveClosedOrder()
    if (orderId) {
        lastOrderId.value = orderId
        reviewPrompt.value = true
    }
}, { immediate: true })
const modal = ref(null)
const sel = reactive({ groups: {} })
const qty = ref(1)

const hasOverlay = computed(() => Boolean(
    modal.value || cartDrawer.value || navDrawer.value || infoOpen.value || userInfoDialog.value || orderSuccess.value || reviewPrompt.value
))

// Closing the order confirmation just dismisses it. The feedback prompt is no
// longer offered here — it waits until the order is closed and the diner
// returns (see the reviewsEnabled watcher above).
function closeOrderSuccess() {
    orderSuccess.value = false
}

watch(hasOverlay, (locked) => {
    document.body.style.overflow = locked ? 'hidden' : ''
}, { immediate: true })

function closeTopOverlay(event) {
    if (event.key !== 'Escape') return
    if (modal.value) closeModal()
    else if (cartDrawer.value) cartDrawer.value = false
    else if (navDrawer.value) navDrawer.value = false
    else if (infoOpen.value) infoOpen.value = false
    else if (userInfoDialog.value) closeDialog()
    else if (orderSuccess.value) closeOrderSuccess()
    else if (reviewPrompt.value) reviewPrompt.value = false
}

onMounted(() => window.addEventListener('keydown', closeTopOverlay))
onUnmounted(() => {
    window.removeEventListener('keydown', closeTopOverlay)
    document.body.style.overflow = ''
})

// Menu presentation theme: 'photo' (default image cards), 'text-grid'
// (image-less cards, same grid), or 'text-list' (compact rows). Driven
// per-restaurant by the API's menu_layout; a ?layout= query param overrides it
// for previewing the themes before the dashboard control ships.
const LAYOUTS = ['photo', 'text-grid', 'text-list']
const layoutOverride = new URLSearchParams(window.location.search).get('layout')
const menuLayout = computed(() => {
    if (LAYOUTS.includes(layoutOverride)) return layoutOverride
    const l = restaurant.value?.menu_layout
    return LAYOUTS.includes(l) ? l : 'photo'
})

const accent = computed(() => restaurant.value?.brand_color || '#f59e0b')
// Modals (ItemModal, CartDrawer, …) render via <Teleport to="body">, outside
// .site-shell where --accent is set — so they'd fall back to the default colour.
// Mirror the tenant accent onto the document root so every teleported overlay
// inherits the client's brand colour too.
watch(accent, (c) => {
    document.documentElement.style.setProperty('--accent', c)
    document.documentElement.style.setProperty('--acc', c)
}, { immediate: true })
const sym = computed(() => {
    const r = restaurant.value
    // Egypt: EGP in English, ج.م in Arabic; other currencies keep the API symbol.
    if (r?.currency === 'EGP') return isAr.value ? 'ج.م' : 'EGP'
    return r?.currency_symbol || r?.currency || ''
})
const waDigits = computed(() => (restaurant.value?.whatsapp_number || '').replace(/[^0-9]/g, ''))
// Ordering is off for display-only menus, and also whenever a table QR was
// scanned from outside the branch's geofence (or before presence is confirmed):
// the diner can still browse, but can't add to cart or check out.
const orderingEnabled = computed(() => restaurant.value?.ordering_enabled !== false && !orderingBlocked.value)
const bilingual = computed(() => restaurant.value?.bilingual !== false)
// How checkout completes: 'whatsapp' (WhatsApp only, no record), 'system'
// (order record only, no WhatsApp), or 'both' (record + WhatsApp).
const orderingMode = computed(() => restaurant.value?.ordering_mode || 'both')
const usesWhatsapp = computed(() => orderingMode.value !== 'system')
const usesSystem = computed(() => orderingMode.value !== 'whatsapp')
// WhatsApp-only: the order is recorded PENDING and the restaurant messages the
// diner back once an employee accepts it, so there is no handoff at checkout.
const pendingOrder = computed(() => orderingMode.value === 'whatsapp')
// A WhatsApp handoff needs a number; a system-only menu does not. A resolved
// order type is also required so a dine-in-only menu can't place a table-less
// order from the general link (see orderTypes below).
const canOrder = computed(() => cartCount.value > 0 && !!orderType.value && (!usesWhatsapp.value || pendingOrder.value || !!waDigits.value))

// Order type. Driven by the restaurant's enabled features (pickup/delivery);
// at a scanned table it is dine-in only. Older payloads without order_types
// fall back to both so nothing regresses.
const orderType = ref('pickup')
const orderTypes = computed(() => {
    // Dine-in is bound to a physical table by the table QR session, so it is
    // only offered at a scanned table (there it's the sole option). Off a
    // scanned table there is no table to route a dine-in order to, so the
    // general menu link exposes just the takeaway channels — a manual dine-in
    // pick here would reach the kitchen with no table number.
    if (hasTable.value) return [{ value: 'dine_in', label: t('dine_in') }]
    const enabled = restaurant.value?.order_types ?? ['pickup', 'delivery']
    return enabled.filter(v => v !== 'dine_in').map(v => ({ value: v, label: t(v) }))
})
// Keep the selected type valid as options load / change.
watch(orderTypes, (opts) => {
    if (!opts.some(o => o.value === orderType.value)) orderType.value = opts[0]?.value || ''
}, { immediate: true })
const orderTypeLabel = computed(() => orderTypes.value.find(o => o.value === orderType.value)?.label || '')

const modalGroups = computed(() => {
    if (!modal.value) return []
    return modal.value.kind === 'item' ? (modal.value.ref.option_groups || []) : (modal.value.ref.groups || [])
})

const modalValid = computed(() => {
    return modalGroups.value.every((g, gi) => {
        const need = modal.value.kind === 'combo' ? true : (!!g.is_required || !!g.is_variant)
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

// Pre-select the first option of every single-choice group that must be
// answered (a size/portion variant, a required group, or any combo group), so
// size/type opens with a sensible default instead of an empty required field.
// Multi-select and optional groups start empty.
function defaultSelection(kind, ref_) {
    const groups = kind === 'item' ? (ref_.option_groups || []) : (ref_.groups || [])
    const out = {}
    groups.forEach((g, gi) => {
        const single = (g.max_select || 1) === 1
        const mustAnswer = kind === 'combo' || !!g.is_required || !!g.is_variant
        const opts = kind === 'item' ? (g.options || []) : (g.items || [])
        if (single && mustAnswer && opts.length) out[gi] = 0
    })
    return out
}

function openModal(kind, ref_) {
    modal.value = { kind, ref: ref_ }
    sel.groups = defaultSelection(kind, ref_)
    qty.value = 1
}

function closeModal() {
    modal.value = null
}

function addToCartHandler(note) {
    if (!orderingEnabled.value || !modalValid.value) return
    track('menu_add_to_cart', { slug, kind: modal.value.kind })
    addToCart(modal.value.kind, modal.value.ref, sel.groups, qty.value, note)
    // Just add and bump the header count — don't pop the cart dialog open.
    closeModal()
}

// Total quantity of an item across all its cart lines (variants + notes).
function cartQtyOf(kind, item) {
    return cart.value
        .filter(l => l.kind === kind && l.ref?.id === item?.id)
        .reduce((n, l) => n + l.qty, 0)
}

// Quick-add from the menu card. Items with options can't be added blindly —
// open the modal so the diner picks them; simple items add one directly.
function quickAdd(kind, item) {
    if (!orderingEnabled.value) return
    const groups = kind === 'combo' ? (item.groups || []) : (item.option_groups || [])
    if (groups.length) { openModal(kind, item); return }
    track('menu_add_to_cart', { slug, kind })
    addToCart(kind, item, {}, 1, '')
}

// Quick-remove: drop one from the most recently added line of this item.
function quickRemove(kind, item) {
    const lines = cart.value.filter(l => l.kind === kind && l.ref?.id === item?.id)
    const last = lines[lines.length - 1]
    if (last) bumpLine(last.uid, -1)
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
    lastOrderId.value = null
    const snapshot = {
        items: cart.value.map(line => ({
            // What was ordered, by id: the server prices the line from these
            // and names it (XORD-047). The fields below are display text the
            // server ignores; they stay for the WhatsApp message's sake.
            kind: line.kind === 'combo' ? 'combo' : 'item',
            menu_item_id: line.kind === 'combo' ? undefined : line.ref.id,
            combo_id: line.kind === 'combo' ? line.ref.id : undefined,
            option_ids: getLineOptionIds(line),
            name: localize(line.ref),
            qty: line.qty,
            // Size/portion travels on its own so the dashboard can show it next
            // to the name; `options` carries only the add-ons.
            variant: getLineVariant(line, localize),
            options: getLineExtras(line, localize),
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
        lang: locale.value === 'en' ? 'en' : 'ar',
    }
    // System / both modes persist a durable order record; WhatsApp / both modes
    // open the WhatsApp handoff. Fire-and-forget so window.open stays inside the
    // user gesture; the order code fills into the success dialog when it lands.
    // Kept so a refused order can be put back in the basket (XORD-047).
    const placed = cart.value.slice()
    orderError.value = ''
    if (usesSystem.value || pendingOrder.value) {
        postOrder(slug, snapshot)
            .then(res => {
                lastOrderCode.value = res?.data?.code || ''
                lastOrderId.value = res?.data?.id || null
                // Stash it so its close, on the diner's next visit, invites feedback.
                if (lastOrderId.value) rememberPendingReview(lastOrderId.value)
            })
            .catch((err) => {
                // In 'both' mode the WhatsApp handoff still carries the order.
                // System-only, the server's answer is all there is: an order it
                // refused (an old tab, an item gone) must not be shown as
                // received, and the diner keeps the basket to try again.
                if (usesWhatsapp.value && !pendingOrder.value) return
                orderError.value = err?.response?.data?.message || t('order_not_placed_hint')
                cart.value = placed
            })
    }

    if (usesWhatsapp.value && !pendingOrder.value) {
        sendToWhatsApp(orderData, waDigits.value, t)
    }
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
    <div :style="{ '--accent': accent, '--acc': accent }" :data-layout="menuLayout" class="site-shell">
        <!-- Exactly one <main> per state: the skeleton while the payload loads,
             the message on failure, and .page-wrap once the menu renders. The
             loading one is marked busy so a screen reader is told the region is
             still filling rather than finding it empty. -->
        <main v-if="loading" :aria-label="t('main_content')" aria-busy="true">
            <MenuSkeleton />
        </main>

        <main v-else-if="error || unavailable" :aria-label="t('main_content')" class="min-h-screen grid place-items-center text-center px-6">
            <div class="space-y-4">
                <p class="text-lg text-stone-500">{{ unavailable ? t('unavailable') : t('error_generic') }}</p>
                <button v-if="error && !unavailable" @click="loadMenu" class="px-5 py-2.5 rounded-xl font-semibold text-white" :style="{ background: accent }">{{ t('try_again') }}</button>
            </div>
        </main>

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
                @openInfo="infoOpen = true"
            />

            <div v-if="hasTable" class="table-banner">
                <div class="table-banner__identity">
                    <span class="table-banner__pin">◈</span>
                    <span>{{ isAr ? 'طاولة' : 'Table' }} {{ tableLabel }}<span v-if="tableAreaName"> — {{ tableAreaName }}</span></span>
                </div>
                <BillRequestButton
                    v-if="billRequests"
                    :sessionToken="sessionToken"
                    :tableLabel="tableLabel"
                    :t="t"
                />
            </div>
            <div v-else-if="locating" class="table-banner">{{ t('loc_checking') }}</div>
            <div v-else-if="tableError" class="table-banner table-banner--error">
                <span>{{ tableError }}</span>
                <button v-if="canRetryLocation" type="button" class="table-banner__retry" @click="retryTable">{{ t('try_again') }}</button>
            </div>

            <main class="page-wrap" :aria-label="t('main_content')">
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
                        :orderingEnabled="orderingEnabled"
                        :scrollLocked="spyLocked"
                        :t="t"
                        :money="money"
                        :localize="localize"
                        :cartQty="cartQtyOf"
                        @openModal="openModal"
                        @quickAdd="quickAdd"
                        @quickRemove="quickRemove"
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
            </main>

            <Footer :t="t" :socials="restaurant?.social_links" />

            <CartDrawer
                v-if="orderingEnabled && cartDrawer"
                :isOpen="cartDrawer"
                :cart="cart"
                :cartCount="cartCount"
                :cartTotal="cartTotal"
                :canOrder="canOrder"
                :viaWhatsapp="usesWhatsapp && !pendingOrder"
                :isSubmitting="submittingOrder"
                :orderType="orderType"
                :orderTypes="orderTypes"
                :userInfo="userInfo"
                :isAr="isAr"
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

            <button
                v-if="orderingEnabled && cartCount > 0 && !hasOverlay"
                type="button"
                class="mobile-cart-bar"
                @click="cartDrawer = true"
            >
                <span class="mobile-cart-bar__icon" aria-hidden="true">🛒</span>
                <span class="mobile-cart-bar__label">{{ t('view_cart') }}</span>
                <span class="mobile-cart-bar__count">{{ cartCount }}</span>
                <strong>{{ money(cartTotal) }}</strong>
            </button>

            <ItemModal
                v-if="modal"
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
                v-if="orderSuccess"
                :isOpen="orderSuccess"
                :reopenUrl="lastOrderUrl"
                :orderCode="lastOrderCode"
                :viaWhatsapp="usesWhatsapp && !pendingOrder"
                :pending="pendingOrder"
                :errorMessage="orderError"
                :t="t"
                @close="closeOrderSuccess"
            />

            <ReviewPromptModal
                v-if="reviewsEnabled && reviewPrompt"
                :isOpen="reviewPrompt"
                :slug="slug"
                :locale="locale"
                :sessionToken="sessionToken"
                :orderId="lastOrderId"
                :publicReviewUrl="restaurant?.review_public_url || ''"
                :thankYou="restaurant?.review_thank_you || ''"
                :customerName="userInfo.name || ''"
                :customerPhone="userInfo.phone || ''"
                :t="t"
                @close="reviewPrompt = false"
            />

            <SideMenu
                v-if="navDrawer"
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

            <RestaurantInfoModal
                v-if="infoOpen"
                :restaurant="restaurant"
                :isAr="isAr"
                :t="t"
                :localize="localize"
                @close="infoOpen = false"
            />

            <UserInfoDialog
                v-if="userInfoDialog"
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
