<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@xorder/ui/i18n'
import Icon from '@xorder/ui/Icon.vue'
import { fetchLandingContent, postLead } from './lib/content.js'
import { isValidMobile } from './lib/phone.js'
import { track } from './lib/analytics.js'
import { vReveal } from './lib/reveal.js'
import HeroVisual from './components/HeroVisual.vue'
import WhatsappStory from './components/WhatsappStory.vue'
import WaFloat from './components/WaFloat.vue'
// Transparent PNG (the shared ui logo has a white background, which shows as a
// box on the cream page).
import logoUrl from './assets/xorder-logo.png'

const { t, tm, rt, locale } = useI18n()

// Page copy lives in src/i18n/messages.js (namespace `lp`). The landing-content
// API still supplies the live data: pricing plans, industry images, demo menus,
// WhatsApp number, login link and SEO. Sections render once it has loaded.
const content = ref(null)
const loadError = ref(false)

// Pick the active locale from a bilingual { en, ar } field.
const L = (field) => (field && (field[locale.value] ?? field.en)) || ''

// ---- Header: mobile drawer + scroll spy ----------------------------------
const navOpen = ref(false)
const activeSection = ref('home')
const scrolled = ref(false)

// The anchor sections the header links to, in document order.
const NAV = [
    { id: 'home', key: 'lp.nav.home' },
    { id: 'features', key: 'lp.nav.features' },
    { id: 'how', key: 'lp.nav.how' },
    { id: 'packages', key: 'lp.nav.packages' },
    { id: 'industries', key: 'lp.nav.industries' },
    { id: 'faq', key: 'lp.nav.faq' },
]

// Feature groups. Labels reuse the shared `feature.*` names where the platform
// has one, so the landing and the plan cards call a feature the same thing.
const FEATURE_GROUPS = [
    { id: 'menu', tone: 'amber', title: 'lp.features.g_menu', sub: 'lp.features.g_menu_sub', items: [
        { label: 'feature.qr_menu', d: 'qr_menu' },
        { label: 'lp.features.live_updates', d: 'live_updates' },
        { label: 'lp.features.bilingual', d: 'bilingual' },
        { label: 'feature.multi_branch', d: 'multi_branch' },
    ] },
    { id: 'orders', tone: 'green', title: 'lp.features.g_orders', sub: 'lp.features.g_orders_sub', items: [
        { label: 'feature.whatsapp_ordering', d: 'whatsapp_ordering' },
        { label: 'feature.system_ordering', d: 'system_ordering' },
        { label: 'feature.pickup_delivery', d: 'pickup_delivery' },
        { label: 'feature.guest_paging', d: 'guest_paging' },
    ] },
    { id: 'venue', tone: 'amber', title: 'lp.features.g_venue', sub: 'lp.features.g_venue_sub', items: [
        { label: 'feature.dine_in', d: 'dine_in' },
        { label: 'feature.table_management', d: 'table_management' },
        { label: 'feature.bill_requests', d: 'bill_requests' },
    ] },
    { id: 'insights', tone: 'green', title: 'lp.features.g_insights', sub: 'lp.features.g_insights_sub', items: [
        { label: 'feature.customer_tracking', d: 'customer_tracking' },
        { label: 'feature.internal_reviews', d: 'internal_reviews' },
        { label: 'feature.product_analytics', d: 'product_analytics' },
    ] },
]

function closeNav() { navOpen.value = false }
function onNavClick(id) { closeNav(); activeSection.value = id }

let spy = null
function onScroll() { scrolled.value = window.scrollY > 8 }

// Wait one paint so section elements exist before observing them.
function nextFramePaint() {
    return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
}

onMounted(async () => {
    window.addEventListener('scroll', onScroll, { passive: true })
    onScroll()
    try {
        content.value = await fetchLandingContent()
        applySeo(content.value.seo)
        // Highlight the nav link for whichever section is in view.
        await nextFramePaint()
        spy = new IntersectionObserver(
            (entries) => {
                entries.forEach((e) => { if (e.isIntersecting) activeSection.value = e.target.id })
            },
            { rootMargin: '-45% 0px -50% 0px', threshold: 0 },
        )
        NAV.forEach(({ id }) => {
            const el = document.getElementById(id)
            if (el) spy.observe(el)
        })
    } catch {
        loadError.value = true
    }
})

onBeforeUnmount(() => {
    window.removeEventListener('scroll', onScroll)
    spy?.disconnect()
})

// Keep the document title/meta in sync if the language changes after load.
watch(locale, () => { if (content.value) applySeo(content.value.seo) })
// Lock body scroll while the mobile drawer is open.
watch(navOpen, (open) => { document.body.style.overflow = open ? 'hidden' : '' })

function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar'); closeNav() }
const targetLocaleKey = () => (locale.value === 'ar' ? 'languages.en' : 'languages.ar')
const targetLocaleAriaKey = () => (locale.value === 'ar' ? 'common.switch_to_english' : 'common.switch_to_arabic')

// ---- Derived links -------------------------------------------------------
// Optional demo tabs (one per venue type); with fewer than two we show the
// single demo from demo.restaurant_slug, exactly as before.
const demoTabs = computed(() => (content.value?.demo?.tabs || []).filter((tb) => tb?.restaurant_slug))
const activeDemoTab = ref(0)
const demoSlug = computed(() =>
    (demoTabs.value.length > 1 ? demoTabs.value[activeDemoTab.value]?.restaurant_slug : null)
    || content.value?.demo?.restaurant_slug || 'mahsoub-restaurnt')
function pickDemoTab(i) { activeDemoTab.value = i; demoQrOk.value = true }
function onTabKey(e) {
    const n = demoTabs.value.length
    const d = { ArrowRight: 1, ArrowLeft: -1 }[e.key] * (locale.value === 'ar' ? -1 : 1)
    if (!d) return
    e.preventDefault()
    pickDemoTab((activeDemoTab.value + d + n) % n)
    document.getElementById(`lp-demo-tab-${activeDemoTab.value}`)?.focus()
}
// Business types: image/icon per card is admin-managed (super-admin → Industries).
const industries = computed(() => (content.value?.industries?.items || []).filter((it) => it && (L(it.text) || it.image)))
const loginHref = computed(() => content.value?.hero?.login_link || '')
// Demo menu link: in production use the canonical {slug}.host/menu subdomain form
// real QR codes encode (Restaurant::publicUrl); on localhost fall back to the
// always-available /r/{slug} path so the demo link works in dev too.
const demoMenuUrl = computed(() => {
    const host = window.location.host.replace(/^www\./, '')
    const isLocal = /^(localhost|127\.|\[?::1)/i.test(host)
    return isLocal
        ? `/r/${demoSlug.value}`
        : `${window.location.protocol}//${demoSlug.value}.${host}/menu`
})
// Real, scannable QR for the demo restaurant, rendered server-side (SVG).
const demoQrUrl = computed(
    () => `${import.meta.env.VITE_API_URL || ''}/api/public/restaurants/${demoSlug.value}/qr`,
)
const heroPrimaryLink = computed(() => content.value?.hero?.primary_link || '#lead')
const heroSecondaryLink = computed(() => content.value?.hero?.secondary_link || demoMenuUrl.value)

const waNumber = computed(() =>
    (content.value?.whatsapp?.number || content.value?.contact?.whatsapp || '').replace(/[^0-9]/g, ''))
const waHref = computed(() => {
    if (!waNumber.value) return ''
    const msg = L(content.value?.whatsapp?.default_message)
    return `https://wa.me/${waNumber.value}${msg ? `?text=${encodeURIComponent(msg)}` : ''}`
})
const floatingWa = computed(() => content.value?.whatsapp?.floating_enabled !== false && !!waHref.value)

// ---- Packages ------------------------------------------------------------
// Cards are generated by the API from the Plans catalog (/plans): each carries
// a numeric `price` (null = custom, 0 = free), a `currency` code, and the
// plan's `feature_keys` — localized to bullets here via the shared feature.*
// labels.
const enabledPlans = computed(() => (content.value?.pricing?.plans || []).filter((p) => p.enabled !== false))
const planRecommended = (p) => p.recommended ?? p.popular ?? false

// Union of every feature offered by any plan, in first-seen order (base plan's
// features first, richer plans append theirs). Rendering the SAME rows on every
// card — checked when included, dimmed when not — keeps the cards equal height
// and turns them into a real side-by-side comparison instead of ragged lists.
// `multi_branch` is intentionally omitted — branch allowance is already shown
// in the dedicated branches row, so listing it again as a bullet is redundant.
const HIDDEN_FEATURE_KEYS = new Set(['multi_branch'])
// pickup + delivery are collapsed into a single "استلام وتوصيل" row.
const MERGE_FEATURE_KEYS = { pickup: 'pickup_delivery', delivery: 'pickup_delivery' }
// The customer directory isn't a standalone flag: it's available whenever the
// plan takes orders (WhatsApp or System), because customers are captured from
// orders. A menu-only plan (QR, no ordering) can't build a customer list.
const hasOrdering = (p) => (p.feature_keys || []).some((k) => k === 'whatsapp_ordering' || k === 'system_ordering')
const allFeatureKeys = computed(() => {
    const seen = new Set()
    const keys = []
    const add = (k) => { if (!seen.has(k) && !HIDDEN_FEATURE_KEYS.has(k)) { seen.add(k); keys.push(k) } }
    for (const p of enabledPlans.value) {
        for (const k of p.feature_keys || []) add(MERGE_FEATURE_KEYS[k] || k)
    }
    // Always a comparison row — ticked only on plans that take orders.
    add('customer_tracking')
    return keys
})
const planHasFeature = (p, key) => {
    const fk = p.feature_keys || []
    if (key === 'customer_tracking') return hasOrdering(p)
    if (key === 'pickup_delivery') return fk.includes('pickup') || fk.includes('delivery')
    return fk.includes(key)
}
// The last feature (in display order) the plan actually includes — the branch
// allowance row is rendered right after it, grouping it with what's active.
const lastActiveKey = (p) => {
    const active = allFeatureKeys.value.filter((k) => planHasFeature(p, k))
    return active.length ? active[active.length - 1] : null
}

// Localized currency glyphs: the API sends the ISO code; Arabic gets the native
// symbol, other locales fall back to the code.
const AR_CURRENCY = { EGP: 'ج.م', SAR: 'ر.س', AED: 'د.إ', USD: '$', KWD: 'د.ك', QAR: 'ر.ق', BHD: 'د.ب', OMR: 'ر.ع', JOD: 'د.أ', EUR: '€', GBP: '£' }
const currencySymbol = (code) => (locale.value === 'ar' ? (AR_CURRENCY[code] || code) : code)

// The price line shown on a card: custom pricing, free, or the monthly amount.
function planPrice(p) {
    if (p.price === null || p.price === undefined) return t('landing.price_custom')
    const amount = Number(p.price)
    if (amount === 0) return t('landing.price_free')
    const num = new Intl.NumberFormat(locale.value === 'ar' ? 'ar-EG' : 'en-US').format(amount)
    return `${num} ${currencySymbol(p.currency)} ${t('landing.price_per_month')}`
}

// Branch allowance shown on a card: a single branch unless the plan grants
// multi-branch, then either a numeric cap or unlimited.
function planBranches(p) {
    if (!(p.feature_keys || []).includes('multi_branch')) return t('landing.branches_one')
    if (p.max_branches === null || p.max_branches === undefined) return t('landing.branches_unlimited')
    return t('landing.branches_upto', { n: p.max_branches })
}

// A missing demo restaurant makes the server-rendered QR 404; hide it cleanly
// rather than showing a broken-image icon (the brief: images must not break layout).
const demoQrOk = ref(true)

// ---- FAQ accordion (copy in src/i18n/messages.js) -------------------------
const openFaq = ref(0) // single-open accordion; -1 = all closed
function toggleFaq(i) { openFaq.value = openFaq.value === i ? -1 : i }

// ---- Analytics handlers --------------------------------------------------
const onRequestDemo = () => track('landing_request_demo_clicked')
const onViewDemo = () => track('landing_view_demo_clicked')
const onWhatsapp = () => track('landing_whatsapp_clicked')
const onPackageCta = (name) => track('landing_package_cta_clicked', { package: name })

// ---- Lead form -----------------------------------------------------------
const businessTypes = computed(() => [
    t('landing.bt_restaurant'), t('landing.bt_cafe'), t('landing.bt_dessert'),
    t('landing.bt_cloud'), t('landing.bt_truck'), t('landing.bt_takeaway'),
    t('landing.bt_brand'), t('landing.bt_other'),
])

const form = reactive({
    restaurant_name: '', contact_name: '', whatsapp: '',
    city: '', business_type: '', message: '',
    website: '', // honeypot — hidden from humans; the API drops leads that fill it
})
const submitting = ref(false)
const submitted = ref(false)
const formErrors = ref({})

async function submitLead() {
    formErrors.value = {}
    // Catch a malformed number before the round-trip; the server re-validates.
    if (!isValidMobile(form.whatsapp)) {
        formErrors.value = { whatsapp: [t('landing.lead_whatsapp_invalid')] }
        return
    }
    submitting.value = true
    try {
        await postLead({ ...form, source: 'landing_lead_form' })
        submitted.value = true
        track('landing_lead_submitted')
    } catch (e) {
        if (e.fields) formErrors.value = e.fields
        else formErrors.value = { _: [t('landing.lead_error')] }
    } finally {
        submitting.value = false
    }
}

// ---- SEO -----------------------------------------------------------------
function setMeta(attr, key, value) {
    if (!value) return
    let el = document.head.querySelector(`meta[${attr}="${key}"]`)
    if (!el) {
        el = document.createElement('meta')
        el.setAttribute(attr, key)
        document.head.appendChild(el)
    }
    el.setAttribute('content', value)
}
function applySeo(seo) {
    if (!seo) return
    // SEO fields are bilingual { en, ar }; tolerate legacy plain strings too.
    const pick = (f) => (f && typeof f === 'object' ? L(f) : f)
    const title = pick(seo.title)
    const description = pick(seo.description)
    if (title) document.title = title
    setMeta('name', 'description', description)
    setMeta('property', 'og:title', pick(seo.og_title) || title)
    setMeta('property', 'og:description', pick(seo.og_description) || description)
    setMeta('property', 'og:type', 'website')
    if (seo.og_image) setMeta('property', 'og:image', seo.og_image)
}

const year = new Date().getFullYear()
</script>
<template>
    <div class="theme-warm landing">
        <!-- ============================ Header ============================ -->
        <header class="lp-header" :class="{ 'is-scrolled': scrolled }">
            <div class="lp-container lp-nav">
                <a href="#home" class="lp-brand" @click="onNavClick('home')" :aria-label="t('app.title')">
                    <img :src="logoUrl" alt="XORDER" class="lp-logo" width="107" height="30" />
                </a>

                <nav class="lp-links" :aria-label="t('app.title')">
                    <a v-for="item in NAV" :key="item.id" :href="`#${item.id}`"
                        :class="{ active: activeSection === item.id }"
                        :aria-current="activeSection === item.id ? 'true' : undefined"
                        @click="onNavClick(item.id)">{{ t(item.key) }}</a>
                </nav>

                <div class="lp-actions">
                    <a v-if="loginHref" :href="loginHref" class="lp-login">{{ t('landing.login') }}</a>
                    <a href="#lead" class="btn btn-accent lp-pill lp-cta-nav" @click="onRequestDemo">{{ t('lp.cta_demo') }}</a>
                    <button class="lp-lang" @click="toggleLang" :title="t(targetLocaleKey())"
                        :aria-label="t(targetLocaleAriaKey())">
                        <Icon name="globe" :size="20" />
                    </button>
                    <button class="lp-burger" :aria-expanded="navOpen" aria-controls="lp-drawer"
                        :aria-label="navOpen ? t('landing.close_label') : t('landing.menu_label')"
                        @click="navOpen = !navOpen">
                        <Icon :name="navOpen ? 'close' : 'menu'" :size="24" />
                    </button>
                </div>
            </div>

            <!-- Mobile drawer -->
            <div id="lp-drawer" class="lp-drawer" :class="{ open: navOpen }">
                <nav class="lp-drawer-links" :aria-label="t('app.title')">
                    <a v-for="item in NAV" :key="item.id" :href="`#${item.id}`"
                        :class="{ active: activeSection === item.id }" @click="onNavClick(item.id)">
                        {{ t(item.key) }}
                    </a>
                </nav>
                <div class="lp-drawer-actions">
                    <a v-if="loginHref" :href="loginHref" class="btn btn-ghost lp-pill lp-btn-lg">{{ t('landing.login') }}</a>
                    <a href="#lead" class="btn btn-accent lp-pill lp-btn-lg" @click="onNavClick('home'); onRequestDemo()">{{ t('lp.cta_demo') }}</a>
                </div>
            </div>
        </header>
        <div v-if="navOpen" class="lp-scrim" @click="closeNav" aria-hidden="true"></div>

        <main v-if="content">
            <!-- ============================ Hero ============================ -->
            <section id="home" class="lp-hero">
                <div class="lp-blob lp-blob-1" aria-hidden="true"></div>
                <div class="lp-blob lp-blob-2" aria-hidden="true"></div>
                <div class="lp-container lp-hero-grid">
                    <div class="lp-hero-copy">
                        <span class="lp-hand lp-hello" v-reveal>{{ t('lp.hero.hello') }}</span>
                        <h1 class="lp-h1" v-reveal="0.08">
                            {{ t('lp.hero.title_a') }}<br>{{ t('lp.hero.title_b') }}
                            <span class="lp-underline">{{ t('lp.hero.title_c') }}<svg viewBox="0 0 300 16" preserveAspectRatio="none" aria-hidden="true"><path d="M4 11c60-7 150-9 292-3" /></svg></span>
                        </h1>
                        <div class="lp-hero-cta" v-reveal="0.16">
                            <a :href="heroPrimaryLink" class="btn btn-accent lp-pill lp-btn-lg" @click="onRequestDemo">{{ t('lp.cta_demo') }}</a>
                            <a :href="heroSecondaryLink" class="btn btn-ghost lp-pill lp-btn-lg" @click="onViewDemo">{{ t('lp.cta_live') }}</a>
                        </div>
                    </div>
                    <HeroVisual :qr-url="demoQrUrl" :qr-ok="demoQrOk" @qr-error="demoQrOk = false" />
                </div>
            </section>

            <!-- ========================== Marquee ========================== -->
            <section class="lp-marquee-sec" :aria-label="t('lp.nav.industries')">
                <p class="lp-hand lp-marquee-note">{{ t('lp.marquee.note') }}</p>
                <div class="lp-marquee-wrap">
                    <div class="lp-marquee">
                        <template v-for="copy in 2" :key="copy">
                            <span v-for="(m, i) in tm('lp.marquee.items')" :key="`${copy}-${i}`" class="lp-mq-pill"
                                :aria-hidden="copy === 2 ? 'true' : undefined">
                                <i aria-hidden="true"></i>{{ rt(m) }}
                            </span>
                        </template>
                    </div>
                </div>
            </section>

            <!-- ========================= Features ========================= -->
            <section id="features" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.nav.features') }}</span>
                        <h2 class="lp-h2">{{ t('lp.features.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.features.sub') }}</p>
                    </div>
                    <div class="lp-groups">
                        <div v-for="(g, gi) in FEATURE_GROUPS" :key="g.id" class="lp-card lp-lift lp-group" v-reveal="(gi % 2) * 0.08">
                            <div class="lp-group-head">
                                <span class="lp-ic" :class="`lp-ic-${g.tone}`">
                                    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                        <template v-if="g.id === 'menu'"><rect x="7" y="2.5" width="10" height="19" rx="2.5" /><path d="M10 7h4M10 11h4M10 15h2" /></template>
                                        <template v-else-if="g.id === 'orders'"><path d="M5 8h14l-1 12H6z" /><path d="M9 8V6a3 3 0 016 0v2" /></template>
                                        <template v-else-if="g.id === 'venue'"><path d="M3 9h18" /><path d="M6 9v10M18 9v10" /><path d="M8 5h8" /></template>
                                        <template v-else><path d="M4 20V10M10 20V4M16 20v-7M22 20H2" /></template>
                                    </svg>
                                </span>
                                <span>
                                    <h3 class="lp-group-title">{{ t(g.title) }}</h3>
                                    <span class="lp-group-sub">{{ t(g.sub) }}</span>
                                </span>
                            </div>
                            <ul class="lp-group-list">
                                <li v-for="it in g.items" :key="it.d">
                                    <span class="lp-check"><Icon name="check" :size="12" /></span>
                                    <span>
                                        <strong>{{ t(it.label) }}</strong>
                                        <span>{{ t(`lp.features.d.${it.d}`) }}</span>
                                    </span>
                                </li>
                            </ul>
                        </div>
                    </div>
                    <p class="lp-footnote" v-reveal>{{ t('lp.features.footnote') }}</p>
                </div>
            </section>

            <!-- ============== Dashboard day + WhatsApp story ============== -->
            <section id="showcase" class="lp-section lp-showcase-sec">
                <div class="lp-container">
                    <div class="lp-split">
                        <div v-reveal>
                            <span class="lp-eyebrow">{{ t('lp.dash.eyebrow') }}</span>
                            <h2 class="lp-h2">{{ t('lp.dash.title') }}</h2>
                            <p class="lp-sub lp-narrow">{{ t('lp.dash.text') }}</p>
                            <div class="lp-pills">
                                <span v-for="(p, i) in tm('lp.dash.pills')" :key="i">{{ rt(p) }}</span>
                            </div>
                        </div>
                        <div class="lp-card lp-day" v-reveal="0.1">
                            <div class="lp-day-head">
                                <strong>{{ t('lp.dash.day_title') }}</strong>
                                <span class="lp-hand">{{ t('lp.dash.example') }}</span>
                            </div>
                            <ol>
                                <li v-for="(d, i) in tm('lp.dash.day')" :key="i" v-reveal="i * 0.08">
                                    <span class="lp-day-time">{{ rt(d.time) }}</span>
                                    <span>{{ rt(d.text) }}</span>
                                </li>
                            </ol>
                        </div>
                    </div>
                    <div class="lp-gap-xl"></div>
                    <WhatsappStory />
                </div>
            </section>

            <!-- ======================== Why digital ======================== -->
            <div class="lp-squiggle" v-reveal aria-hidden="true">
                <svg viewBox="0 0 1440 80" preserveAspectRatio="none"><path d="M0 44 C 240 60, 420 30, 640 40 C 700 43, 760 52, 790 40 C 830 24, 770 8, 720 16 C 670 24, 690 52, 760 54 C 960 60, 1180 30, 1440 36" /></svg>
            </div>
            <section id="why" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.why.eyebrow') }}</span>
                        <h2 class="lp-h2">{{ t('lp.why.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.why.sub') }}</p>
                    </div>
                    <ul class="lp-why">
                        <li v-for="(w, i) in tm('lp.why.items')" :key="i" class="lp-card lp-lift" v-reveal="(i % 2) * 0.08">
                            <span class="lp-ic lp-ic-sm" :class="i === 2 ? 'lp-ic-green' : 'lp-ic-amber'">
                                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                    <template v-if="i === 0"><path d="M7 8V3h10v5" /><rect x="3" y="8" width="18" height="9" rx="2" /><path d="M7 14h10v7H7z" /></template>
                                    <template v-else-if="i === 1"><rect x="7" y="2.5" width="10" height="19" rx="2.5" /><path d="M11 18.5h2" /></template>
                                    <template v-else-if="i === 2"><path d="M5 19c0-8 5-13 15-14-1 10-6 15-14 15" /><path d="M5 19l7-7" /></template>
                                    <template v-else><path d="M13 2L4 14h7l-1 8 9-12h-7z" /></template>
                                </svg>
                            </span>
                            {{ rt(w) }}
                        </li>
                    </ul>
                </div>
            </section>

            <!-- =================== How it works + Live demo ================ -->
            <section id="how" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.nav.how') }}</span>
                        <h2 class="lp-h2">{{ t('lp.how.title') }}</h2>
                    </div>
                    <ol class="lp-steps">
                        <li v-for="(s, i) in tm('lp.how.steps')" :key="i" class="lp-card lp-lift lp-step" v-reveal="i * 0.08">
                            <span class="lp-step-num">{{ i + 1 }}</span>
                            <h3 class="lp-step-title">{{ rt(s.title) }}</h3>
                            <p class="lp-step-text">{{ rt(s.text) }}</p>
                        </li>
                    </ol>

                    <div v-if="content.demo?.enabled !== false" class="lp-how-demo">
                        <div v-if="demoTabs.length > 1" class="lp-tabs" role="tablist" :aria-label="t('lp.how.demo_tabs')" @keydown="onTabKey">
                            <button v-for="(tb, i) in demoTabs" :key="i" :id="`lp-demo-tab-${i}`" aria-controls="lp-demo-panel" type="button" role="tab"
                                class="lp-tab" :class="{ on: i === activeDemoTab }" :aria-selected="i === activeDemoTab"
                                :tabindex="i === activeDemoTab ? 0 : -1" @click="pickDemoTab(i)">{{ L(tb.label) }}</button>
                        </div>
                        <div id="lp-demo-panel" class="lp-demo-grid" :role="demoTabs.length > 1 ? 'tabpanel' : undefined" :aria-labelledby="demoTabs.length > 1 ? `lp-demo-tab-${activeDemoTab}` : undefined">
                            <div class="lp-demo-card" :class="{ 'lp-demo-card-empty': !demoQrOk }" v-reveal>
                                <img v-show="demoQrOk" class="lp-qr-img" :src="demoQrUrl" width="200" height="200" alt="" loading="lazy" @error="demoQrOk = false" />
                                <div class="lp-hand lp-demo-stand">{{ t('lp.how.demo_stand') }}</div>
                            </div>
                            <div class="lp-demo-copy" v-reveal="0.1">
                                <span class="lp-eyebrow">{{ t('lp.how.demo_eyebrow') }}</span>
                                <h3 class="lp-demo-title">{{ t('lp.how.demo_title') }}</h3>
                                <p class="lp-sub">{{ t('lp.how.demo_text') }}</p>
                                <a :href="demoMenuUrl" target="_blank" rel="noopener" class="btn btn-accent lp-pill lp-btn-lg" @click="onViewDemo">{{ t('lp.how.demo_btn') }}</a>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ========================= Packages ========================= -->
            <section id="packages" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.nav.packages') }}</span>
                        <h2 class="lp-h2">{{ t('lp.pkg.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.pkg.sub') }}</p>
                    </div>
                    <div class="lp-pricing-grid">
                        <div class="lp-card lp-lift lp-plan" v-for="(plan, i) in enabledPlans" :key="i" :class="{ 'lp-plan-popular': planRecommended(plan) }" v-reveal="(i % 3) * 0.08">
                            <span v-if="planRecommended(plan)" class="lp-plan-badge">{{ t('lp.pkg.popular') }}</span>
                            <h3 class="lp-plan-name">{{ plan.name }}</h3>
                            <div class="lp-plan-price">
                                <span class="lp-plan-amount">{{ planPrice(plan) }}</span>
                            </div>
                            <ul class="lp-plan-feats">
                                <template v-for="key in allFeatureKeys" :key="key">
                                    <li :class="{ 'is-off': !planHasFeature(plan, key) }">
                                        <span class="lp-check" v-if="planHasFeature(plan, key)"><Icon name="check" :size="12" /></span>
                                        <span class="lp-check lp-check-off" v-else><Icon name="close" :size="12" /></span>
                                        {{ t(`feature.${key}`) }}
                                    </li>
                                    <li v-if="key === lastActiveKey(plan)" class="lp-plan-branches">
                                        <span class="lp-check"><Icon name="store" :size="12" /></span>{{ planBranches(plan) }}
                                    </li>
                                </template>
                            </ul>
                            <a href="#lead" class="btn lp-pill lp-btn-lg lp-plan-cta" :class="planRecommended(plan) ? 'btn-accent' : 'btn-ghost'"
                                @click="onPackageCta(plan.name); onRequestDemo()">
                                {{ t('lp.pkg.choose') }}
                            </a>
                        </div>
                    </div>
                    <p class="lp-hand lp-pkg-note" v-reveal>{{ t('lp.pkg.note') }}</p>
                </div>
            </section>

            <!-- ======================== Industries ======================== -->
            <section id="industries" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.nav.industries') }}</span>
                        <h2 class="lp-h2">{{ t('lp.ind.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.ind.sub') }}</p>
                    </div>
                    <div class="lp-industries">
                        <div class="lp-industry lp-lift" v-for="(it, i) in industries" :key="i"
                            :class="{ 'lp-industry--photo': it.image }"
                            :style="it.image ? { backgroundImage: `url(${it.image})` } : null"
                            v-reveal="(i % 4) * 0.08">
                            <span v-if="!it.image" class="lp-industry-ic" aria-hidden="true">{{ it.icon }}</span>
                            <span class="lp-industry-label">{{ L(it.text) }}</span>
                        </div>
                        <a href="#lead" class="lp-industry lp-industry--more lp-lift" v-reveal="(industries.length % 4) * 0.08" @click="onRequestDemo">
                            <span class="lp-more-plus" aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg></span>
                            <span class="lp-more-text"><strong>{{ t('lp.ind.more') }}</strong><span>{{ t('lp.ind.more_sub') }}</span></span>
                        </a>
                    </div>
                </div>
            </section>

            <!-- =========================== FAQ ============================ -->
            <section id="faq" class="lp-section">
                <div class="lp-container lp-faq-wrap">
                    <div class="lp-section-head" v-reveal>
                        <span class="lp-eyebrow">{{ t('lp.nav.faq') }}</span>
                        <h2 class="lp-h2">{{ t('lp.faq.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.faq.sub') }}</p>
                    </div>
                    <div class="lp-faq">
                        <div class="lp-faq-item" v-for="(item, i) in tm('lp.faq.items')" :key="i" :class="{ open: openFaq === i }" v-reveal="i * 0.05">
                            <h3 class="lp-faq-q">
                                <button type="button" :aria-expanded="openFaq === i" :aria-controls="`lp-faq-panel-${i}`"
                                    :id="`lp-faq-btn-${i}`" @click="toggleFaq(i)">
                                    <span>{{ rt(item.q) }}</span>
                                    <Icon name="chevronDown" :size="18" class="lp-faq-chev" />
                                </button>
                            </h3>
                            <div :id="`lp-faq-panel-${i}`" role="region" :aria-labelledby="`lp-faq-btn-${i}`"
                                class="lp-faq-a" v-show="openFaq === i">
                                <p>{{ rt(item.a) }}</p>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ========================= Lead form ======================== -->
            <section id="lead" class="lp-section lp-section-alt">
                <div class="lp-container lp-lead-grid">
                    <div class="lp-lead-copy" v-reveal>
                        <span class="lp-hand lp-lead-hand">{{ t('lp.lead.hand') }}</span>
                        <h2 class="lp-h2">{{ t('lp.lead.title') }}</h2>
                        <p class="lp-sub">{{ t('lp.lead.sub') }}</p>
                    </div>

                    <div class="lp-card lp-lead-card" v-reveal="0.1">
                        <div v-if="submitted" class="lp-lead-done">
                            <span class="lp-lead-done-ic"><Icon name="check" :size="26" /></span>
                            <p>{{ t('lp.lead.success') }}</p>
                        </div>
                        <form v-else class="lp-form" @submit.prevent="submitLead">
                            <!-- Honeypot: off-screen, skipped by keyboard/screen readers; bots auto-fill it. -->
                            <input v-model="form.website" type="text" name="website" tabindex="-1" autocomplete="off"
                                aria-hidden="true"
                                style="position:absolute;inset-inline-start:-9999px;height:0;width:0;opacity:0;pointer-events:none;" />
                            <label class="lp-field">
                                <span>{{ t('lp.lead.business_name') }} *</span>
                                <input v-model="form.restaurant_name" required maxlength="150" />
                                <small v-if="formErrors.restaurant_name" class="lp-err">{{ formErrors.restaurant_name[0] }}</small>
                            </label>
                            <div class="lp-field-row">
                                <label class="lp-field">
                                    <span>{{ t('landing.lead_contact') }}</span>
                                    <input v-model="form.contact_name" maxlength="150" />
                                </label>
                                <label class="lp-field">
                                    <span>{{ t('landing.lead_whatsapp') }} *</span>
                                    <input v-model="form.whatsapp" required maxlength="40" dir="ltr" placeholder="+20…" data-en-digits />
                                    <small v-if="formErrors.whatsapp" class="lp-err">{{ formErrors.whatsapp[0] }}</small>
                                </label>
                            </div>
                            <div class="lp-field-row">
                                <label class="lp-field">
                                    <span>{{ t('landing.lead_city') }}</span>
                                    <input v-model="form.city" maxlength="100" />
                                </label>
                                <label class="lp-field">
                                    <span>{{ t('landing.lead_business') }}</span>
                                    <select v-model="form.business_type">
                                        <option value="">—</option>
                                        <option v-for="bt in businessTypes" :key="bt" :value="bt">{{ bt }}</option>
                                    </select>
                                </label>
                            </div>
                            <label class="lp-field">
                                <span>{{ t('landing.lead_message') }}</span>
                                <textarea v-model="form.message" rows="3" maxlength="2000" :placeholder="t('lp.lead.message_ph')"></textarea>
                            </label>
                            <p v-if="formErrors._" class="lp-err">{{ formErrors._[0] }}</p>
                            <button type="submit" class="btn btn-accent lp-pill lp-btn-lg lp-form-submit" :disabled="submitting">
                                {{ submitting ? t('landing.lead_sending') : t('lp.lead.submit') }}
                            </button>
                        </form>
                    </div>
                </div>
            </section>

            <!-- ======================== Closing CTA ======================= -->
            <section class="lp-final">
                <div class="lp-container lp-final-inner" v-reveal>
                    <span class="lp-hand lp-final-hand">{{ t('lp.final.eyebrow') }}</span>
                    <h2 class="lp-final-title">{{ t('lp.final.title') }}</h2>
                    <p class="lp-final-sub">{{ t('lp.final.sub') }}</p>
                    <a href="#lead" class="btn lp-pill lp-btn-lg lp-final-btn" @click="onRequestDemo">{{ t('lp.cta_demo') }}</a>
                </div>
            </section>

            <!-- ========================== Footer ========================== -->
            <footer class="lp-footer">
                <div class="lp-container lp-footer-inner">
                    <div class="lp-footer-brand">
                        <img :src="logoUrl" alt="XORDER" class="lp-logo-footer" width="100" height="28" />
                        <div class="lp-footer-tag">{{ t('lp.footer.tagline') }}</div>
                    </div>
                    <nav class="lp-footer-links" :aria-label="t('app.title')">
                        <a v-for="item in NAV" :key="item.id" :href="`#${item.id}`" @click="onNavClick(item.id)">{{ t(item.key) }}</a>
                    </nav>
                    <div class="lp-footer-copy">© {{ year }} {{ t('app.title') }}. {{ t('lp.footer.rights') }}</div>
                </div>
            </footer>
        </main>

        <WaFloat v-if="content && floatingWa" :href="waHref" :label="t('lp.wa_float')" @click="onWhatsapp" />

        <!-- Loading / error states -->
        <div v-if="!content" class="lp-boot">
            <p v-if="loadError" class="lp-boot-msg">{{ t('landing.lead_error') }}</p>
            <div v-else class="lp-boot-spin" role="status" :aria-label="t('common.saving')"></div>
        </div>
    </div>
</template>

<style scoped>
.landing { background: var(--page); color: var(--body); min-height: 100vh;
    /* WCAG AA shades derived from the brand amber (--accent #f89a06) and the
       warm muted grey (--muted #8a7c68). Both brand values are too light to
       carry text on the cream/white surfaces here (white-on-amber is 2.18:1,
       muted-on-cream 3.74:1), so text and any fill that sits *behind* text use
       the deep shades below. The light amber stays for decorative fills,
       blobs, soft tints and emphasis borders, where no text sits on it.
       Landing-local on purpose: --accent/--muted are shared with the
       dashboard and the menu app's per-restaurant theming. */
    --lp-amber: #9c5c02;        /* 5.32:1 on white, 4.80:1 on the alt band, 5.32:1 under white text */
    --lp-amber-hover: #7f4a02;  /* button hover fill — 7.28:1 under white text */
    --lp-muted: #746958;        /* 5.38:1 on white, 4.94:1 on --page, 4.85:1 on the alt band */
    --lp-ease: cubic-bezier(.2,.7,.2,1);
    overflow-x: clip;
}
/* Full-bleed sections; a centered container caps the readable width. */
.lp-container { width: min(calc(100% - 48px), 1200px); margin-inline: auto; }

/* ============================== Header ============================== */
.lp-header { position: sticky; top: 0; z-index: 40; transition: background .2s, border-color .2s, box-shadow .2s;
    background: color-mix(in srgb, var(--page) 88%, transparent); backdrop-filter: blur(12px);
    border-bottom: 1px solid transparent; }
.lp-header.is-scrolled { border-bottom-color: var(--line); box-shadow: 0 6px 24px -20px rgba(42,30,20,.5); }
.lp-nav { display: flex; align-items: center; justify-content: space-between; height: 70px; gap: 20px; }
.lp-brand { display: flex; align-items: center; text-decoration: none; flex: none; }
.lp-logo { height: 30px; width: auto; display: block; }
.lp-links { display: flex; gap: 2px; margin-inline-start: auto; }
.lp-links a { color: var(--body); font-size: 15.5px; text-decoration: none; padding: 8px 12px; border-radius: 10px;
    transition: color .15s, background .15s; }
.lp-links a:hover { color: var(--lp-amber); background: var(--accent-soft); }
.lp-links a.active { color: var(--lp-amber); font-weight: 700; }
.lp-actions { display: flex; align-items: center; gap: 8px; flex: none; }
.lp-lang { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--lp-muted); transition: background .15s, color .15s; }
.lp-lang:hover { background: var(--accent-soft); color: var(--lp-amber); }
.lp-login { color: var(--ink); font-weight: 700; font-size: 15px; text-decoration: none; padding: 9px 14px; border-radius: 10px; }
.lp-login:hover { color: var(--lp-amber); background: var(--accent-soft); }
.lp-cta-nav { padding: 10px 20px; min-height: 44px; }
.lp-burger { display: none; width: 44px; height: 44px; border-radius: 10px; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--ink); }
.lp-drawer { display: none; }
.lp-scrim { position: fixed; inset: 0; z-index: 30; background: rgba(20,14,8,.4); backdrop-filter: blur(2px); }

/* ============================== Buttons ============================= */
.lp-pill { border-radius: 999px; justify-content: center; transition: background .15s, translate .15s; }
.lp-pill:hover { translate: 0 -2px; }
.lp-btn-lg { padding: 13px 26px; font-size: 16px; min-height: 48px; }
/* The shared .btn-accent fills with --accent, which only reaches 2.18:1 under
   white text. Landing pins it to the deep amber (5.32:1). */
.btn-accent { background: var(--lp-amber); }
.btn-accent:hover { background: var(--lp-amber-hover); }

/* ============================ Shared bits =========================== */
.lp-card { background: var(--card); border: 1px solid var(--line); border-radius: 22px; }
.lp-lift { transition: transform .5s var(--lp-ease), box-shadow .5s ease, border-color .3s ease; }
.lp-lift:hover { transform: translateY(-6px); box-shadow: 0 24px 50px -30px rgba(42,30,20,.45); border-color: #f6d7a3; }
.lp-ic { flex: none; width: 52px; height: 52px; border-radius: 16px; display: grid; place-items: center; }
.lp-ic-sm { width: 46px; height: 46px; border-radius: 14px; }
.lp-ic-amber { background: var(--accent-soft); color: var(--lp-amber); }
.lp-ic-green { background: var(--green-soft); color: var(--green); }
.lp-check { display: grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    background: var(--green-soft); color: var(--green); margin-top: 2px; }
.lp-check-off { background: transparent; color: var(--lp-muted); border: 1px solid var(--line); }
.lp-narrow { max-width: 30em; }
.lp-gap-xl { height: clamp(48px, 7vw, 80px); }

/* =============================== Hero ============================== */
.lp-hero { position: relative; padding: clamp(32px, 5vw, 56px) 0 clamp(36px, 5vw, 64px); }
.lp-blob { position: absolute; border-radius: 50%; pointer-events: none; z-index: 0; }
.lp-blob-1 { width: 460px; height: 460px; inset-inline-start: -140px; top: -120px;
    background: radial-gradient(circle, #fde3b8, rgba(254,240,217,0) 70%); animation: lp-drift1 14s ease-in-out infinite; }
.lp-blob-2 { width: 380px; height: 380px; inset-inline-end: 20%; bottom: -160px;
    background: radial-gradient(circle, #d6eedd, rgba(230,243,234,0) 70%); animation: lp-drift2 18s ease-in-out infinite; }
.lp-hero-grid { position: relative; z-index: 1; display: grid; grid-template-columns: 1.1fr .9fr; gap: clamp(24px, 4vw, 56px); align-items: center; }
.lp-hero-copy { display: flex; flex-direction: column; align-items: flex-start; text-align: start; }
.lp-hello { font-size: 26px; color: var(--lp-amber); }
.lp-h1 { font-family: var(--font-display); font-weight: 800; font-size: clamp(36px, 5.5vw, 60px); line-height: 1.15;
    color: var(--ink); margin: 18px 0 0; letter-spacing: -0.01em; }
.lp-underline { position: relative; white-space: nowrap; color: var(--lp-amber); }
.lp-underline svg { position: absolute; inset-inline: 0; bottom: -10px; width: 100%; height: 14px; }
.lp-underline path { fill: none; stroke: var(--accent); stroke-width: 4; stroke-linecap: round;
    stroke-dasharray: 320; animation: lp-draw 1.1s .9s ease-out both; }
.lp-hero-cta { display: flex; gap: 12px; margin-top: 32px; flex-wrap: wrap; }

/* ============================== Marquee ============================ */
.lp-marquee-sec { padding: 8px 0 24px; }
.lp-marquee-note { text-align: center; margin: 0 0 16px; font-size: 22px; color: var(--lp-amber); }
.lp-marquee-wrap { overflow: hidden;
    -webkit-mask-image: linear-gradient(90deg, transparent, #000 10%, #000 90%, transparent);
    mask-image: linear-gradient(90deg, transparent, #000 10%, #000 90%, transparent); }
.lp-marquee { display: flex; width: max-content; gap: 14px; animation: lp-marquee 40s linear infinite; }
[dir='ltr'] .lp-marquee { animation-name: lp-marquee-ltr; }
.lp-marquee-wrap:hover .lp-marquee { animation-play-state: paused; }
.lp-mq-pill { display: inline-flex; align-items: center; gap: 10px; background: var(--card); border: 1px solid var(--line);
    border-radius: 999px; padding: 12px 22px; font-weight: 700; font-size: 16px; color: var(--ink); white-space: nowrap; }
.lp-mq-pill i { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }

/* ============================= Sections ============================ */
.lp-section { padding: clamp(48px, 7vw, 80px) 0; scroll-margin-top: 80px; }
.lp-section-alt { background: color-mix(in srgb, var(--accent-soft) 55%, var(--page)); }
.lp-section-head { text-align: center; max-width: 44em; margin: 0 auto clamp(28px, 4vw, 44px); }

/* Features */
.lp-groups { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 20px; }
.lp-group { padding: 28px 26px 16px; border-radius: 24px; }
.lp-group-head { display: flex; align-items: center; gap: 14px; margin-bottom: 16px; }
.lp-group-title { margin: 0; font-family: var(--font-display); font-weight: 800; font-size: 21px; color: var(--ink); }
.lp-group-sub { font-size: 15px; color: var(--lp-muted); }
.lp-group-list { list-style: none; margin: 0; padding: 0; }
.lp-group-list li { display: flex; align-items: flex-start; gap: 12px; padding: 12px 0; border-top: 1px dashed var(--line); }
.lp-group-list li > span:last-child { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.lp-group-list strong { font-weight: 700; font-size: 16px; color: var(--ink); }
.lp-group-list li > span:last-child > span { font-size: 14.5px; line-height: 1.6; color: var(--lp-muted); }
.lp-footnote { margin: 24px 0 0; text-align: center; font-size: 14px; color: var(--lp-muted); }

/* Dashboard day */
.lp-split { display: grid; grid-template-columns: 1fr 1.15fr; gap: clamp(28px, 5vw, 56px); align-items: center; }
.lp-pills { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 20px; }
.lp-pills span { background: var(--accent-soft); color: var(--lp-amber); font-weight: 700; font-size: 13.5px; padding: 7px 14px; border-radius: 999px; }
.lp-day { padding: 28px; border-radius: 28px; box-shadow: 0 30px 60px -44px rgba(42,30,20,.5); }
.lp-day-head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 8px; }
.lp-day-head strong { font-weight: 800; font-size: 20px; color: var(--ink); }
.lp-day-head .lp-hand { font-size: 20px; color: var(--lp-amber); }
.lp-day ol { list-style: none; margin: 0; padding: 0; }
.lp-day li { display: flex; gap: 16px; padding: 14px 0; border-bottom: 1px dashed var(--line); font-size: 15.5px; line-height: 1.6; }
.lp-day li:last-child { border-bottom: 0; }
.lp-day-time { flex: none; width: 84px; font-weight: 800; color: var(--lp-amber); font-size: 15px; }

/* Squiggle divider */
.lp-squiggle { padding: 8px 0 40px; overflow: hidden; }
.lp-squiggle svg { display: block; width: 100%; height: 70px; }
.lp-squiggle path { fill: none; stroke: var(--accent); stroke-width: 2.5; stroke-linecap: round; stroke-dasharray: 2200; stroke-dashoffset: 2200; }
.lp-squiggle.is-in path, html:not(.lp-reveal) .lp-squiggle path { animation: lp-draw-long 2.4s cubic-bezier(.4,0,.2,1) .2s forwards; }

/* Why */
.lp-why { list-style: none; padding: 0; margin: 0 auto; max-width: 960px; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.lp-why li { display: flex; align-items: center; gap: 14px; padding: 18px 20px; border-radius: 18px; font-size: 16.5px; font-weight: 700; color: var(--ink); }

/* How it works */
.lp-steps { list-style: none; padding: 0; margin: 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; }
.lp-step { padding: 28px 26px; }
.lp-step-num { display: grid; place-items: center; width: 48px; height: 48px; border-radius: 50%; background: var(--lp-amber);
    color: #fff; font-family: var(--font-display); font-weight: 800; font-size: 20px; }
.lp-step-title { font-family: var(--font-display); font-weight: 700; font-size: 19px; color: var(--ink); margin: 18px 0 8px; }
.lp-step-text { font-size: 15.5px; line-height: 1.65; color: var(--lp-muted); margin: 0; }

/* Demo */
.lp-how-demo { margin-top: clamp(32px, 4vw, 48px); padding-top: clamp(28px, 3vw, 40px); border-top: 1px dashed #e2d8c7; }
.lp-demo-grid { display: grid; grid-template-columns: .8fr 1.2fr; gap: clamp(28px, 5vw, 56px); align-items: center; }
.lp-demo-card { background: var(--card); border: 1px solid var(--line); border-radius: 24px; padding: 28px; text-align: center;
    box-shadow: 0 30px 60px -40px rgba(42,30,20,.5); justify-self: center; max-width: 300px; rotate: -2deg; }
.lp-qr-img { width: 100%; max-width: 200px; height: auto; border-radius: 12px; }
.lp-demo-stand { margin-top: 14px; color: var(--lp-amber); font-size: 22px; }
.lp-demo-title { font-family: var(--font-display); font-weight: 800; font-size: clamp(24px, 3vw, 30px); color: var(--ink); margin: 0; }
.lp-demo-copy .btn { margin-top: 24px; }
.lp-tabs { display: flex; flex-wrap: wrap; gap: 8px; justify-content: center; margin-bottom: 28px; }
.lp-tab { border: 1px solid var(--line); background: var(--card); color: var(--ink); cursor: pointer; font-family: var(--font-display);
    font-weight: 700; font-size: 14.5px; padding: 10px 20px; border-radius: 999px; min-height: 44px; }
.lp-tab.on { background: var(--ink); border-color: var(--ink); color: #fff; }

/* Pricing */
.lp-pricing-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px; align-items: stretch; }
.lp-plan { position: relative; border-radius: 24px; padding: 30px 26px; display: flex; flex-direction: column; }
.lp-plan-popular { border-color: var(--accent); box-shadow: 0 30px 60px -38px rgba(248,154,6,.6); }
.lp-plan-badge { position: absolute; top: -12px; inset-inline-start: 26px; background: var(--lp-amber); color: #fff;
    font-family: var(--font-display); font-weight: 700; font-size: 12px; padding: 5px 13px; border-radius: 20px; }
.lp-plan-name { font-family: var(--font-display); font-weight: 800; font-size: 22px; color: var(--ink); margin: 0; }
.lp-plan-price { margin: 18px 0; }
.lp-plan-amount { font-family: var(--font-display); font-weight: 800; font-size: 30px; color: var(--ink); }
.lp-plan-feats { list-style: none; padding: 0; margin: 0 0 24px; display: flex; flex-direction: column; gap: 11px; flex: 1; }
.lp-plan-feats li { display: flex; align-items: flex-start; gap: 10px; font-size: 15px; color: var(--ink); }
.lp-plan-feats li.is-off { color: var(--lp-muted); }
.lp-plan-feats .lp-check { width: 20px; height: 20px; margin-top: 1px; background: var(--green); color: #fff; }
.lp-plan-feats .lp-check-off { background: transparent; color: var(--lp-muted); }
.lp-plan-branches { display: flex; align-items: center; gap: 10px; }
.lp-plan-cta { width: 100%; }
.lp-pkg-note { text-align: center; margin: 28px 0 0; font-size: 24px; color: var(--lp-amber); }

/* Industries */
.lp-industries { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; max-width: 980px; margin: 0 auto; }
.lp-industry { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;
    min-height: 170px; text-align: center; overflow: hidden; background: var(--card); border: 1px solid var(--line);
    border-radius: 22px; padding: 26px 16px; font-family: var(--font-display); font-weight: 700; color: var(--ink); font-size: 16px; }
.lp-industry-ic { font-size: 34px; line-height: 1; }
.lp-industry-label { position: relative; z-index: 1; }
/* Photo variant: image fills the card, label sits over a dark scrim. The scrim
   stays >= .66 alpha across the bottom 40% so white text clears 4.5:1 over any
   admin-uploaded photo. */
.lp-industry--photo { justify-content: flex-end; align-items: stretch; padding: 0; border-color: transparent; color: #fff;
    background-size: cover; background-position: center; }
.lp-industry--photo::before { content: ''; position: absolute; inset: 0;
    background: linear-gradient(to top, rgba(20,12,6,.9), rgba(20,12,6,.66) 40%, rgba(20,12,6,.24) 70%, rgba(20,12,6,.04)); }
.lp-industry--photo .lp-industry-label { padding: 14px 16px; text-align: start; text-shadow: 0 1px 10px rgba(0,0,0,.55); }
.lp-industry--more { justify-content: space-between; align-items: flex-start; text-align: start; padding: 18px 16px;
    background: var(--ink); border-color: var(--ink); color: #fff; text-decoration: none; }
.lp-industry--more:hover { border-color: var(--ink); }
.lp-more-plus { width: 44px; height: 44px; border-radius: 50%; background: var(--accent); color: var(--ink); display: grid; place-items: center; }
.lp-more-text { display: flex; flex-direction: column; gap: 4px; }
.lp-more-text strong { font-weight: 800; font-size: 18px; }
.lp-more-text span { font-weight: 400; font-size: 13.5px; color: #e8dfd2; }

/* FAQ */
.lp-faq-wrap { max-width: 820px; }
.lp-faq { display: flex; flex-direction: column; gap: 12px; }
.lp-faq-item { background: var(--card); border: 1px solid var(--line); border-radius: 18px; overflow: hidden; transition: border-color .15s; }
.lp-faq-item.open { border-color: var(--accent); }
.lp-faq-q { margin: 0; }
.lp-faq-q button { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 16px; min-height: 44px;
    background: none; border: none; cursor: pointer; text-align: start; padding: 20px 22px;
    font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.lp-faq-chev { color: var(--lp-muted); flex-shrink: 0; transition: transform .2s; }
.lp-faq-item.open .lp-faq-chev { transform: rotate(180deg); color: var(--lp-amber); }
.lp-faq-a { padding: 0 22px 22px; }
.lp-faq-a p { margin: 0; font-size: 16px; line-height: 1.7; color: var(--body); }

/* Lead form */
.lp-lead-grid { display: grid; grid-template-columns: 1fr 1.1fr; gap: clamp(28px, 5vw, 56px); align-items: center; }
.lp-lead-copy .lp-sub { max-width: 30em; }
.lp-lead-hand { display: block; font-size: 26px; color: var(--lp-amber); margin-bottom: 8px; }
.lp-lead-card { border-radius: 28px; padding: clamp(22px, 3vw, 32px); box-shadow: 0 30px 60px -42px rgba(42,30,20,.5); }
.lp-form { display: flex; flex-direction: column; gap: 16px; }
.lp-field { display: flex; flex-direction: column; gap: 6px; }
.lp-field > span { font-family: var(--font-display); font-weight: 700; font-size: 14px; color: var(--ink); }
.lp-field input, .lp-field select, .lp-field textarea { width: 100%; padding: 12px 14px; border: 1px solid #e2d8c7;
    border-radius: 14px; background: var(--page); color: var(--ink); font-size: 15px; font-family: inherit; transition: border-color .15s, box-shadow .15s; }
.lp-field input:focus, .lp-field select:focus, .lp-field textarea:focus { outline: none; border-color: var(--lp-amber);
    box-shadow: 0 0 0 3px var(--accent-soft); }
.lp-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.lp-err { color: var(--red); font-size: 13px; }
.lp-form-submit { margin-top: 4px; width: 100%; }
.lp-lead-done { text-align: center; padding: 40px 20px; display: flex; flex-direction: column; align-items: center; gap: 16px; }
.lp-lead-done-ic { display: grid; place-items: center; width: 60px; height: 60px; border-radius: 50%; background: var(--green-soft); color: var(--green); }
.lp-lead-done p { font-size: 17px; color: var(--ink); font-weight: 700; max-width: 22em; }

/* Closing CTA band */
.lp-final { background: var(--ink); color: #fff; padding: clamp(64px, 9vh, 96px) 0; }
.lp-final-inner { display: flex; flex-direction: column; align-items: center; text-align: center; gap: 14px; }
.lp-final-hand { font-size: 28px; color: var(--accent); }
.lp-final-title { font-family: var(--font-display); font-weight: 800; font-size: clamp(28px, 4vw, 40px); line-height: 1.2; max-width: 22em; margin: 0; }
.lp-final-sub { font-size: 17px; color: #e8dfd2; max-width: 36em; line-height: 1.7; margin: 0; }
/* Light amber fill under ink text: 7.9:1 (white on it would fail). */
.lp-final-btn { margin-top: 12px; background: var(--accent); color: var(--ink); }
.lp-final-btn:hover { background: #ffb02e; color: var(--ink); }

/* Footer */
.lp-footer { background: var(--page); border-top: 1px solid var(--line); padding: 44px 0; }
.lp-footer-inner { display: flex; align-items: center; justify-content: space-between; gap: 24px; flex-wrap: wrap; }
.lp-footer-brand { display: flex; flex-direction: column; gap: 10px; align-items: flex-start; }
.lp-logo-footer { height: 28px; width: auto; display: block; }
.lp-footer-tag { font-size: 14px; color: var(--lp-muted); max-width: 26em; }
.lp-footer-links { display: flex; flex-wrap: wrap; gap: 8px 20px; }
.lp-footer-links a { color: var(--body); font-size: 14.5px; text-decoration: none; }
.lp-footer-links a:hover { color: var(--lp-amber); }
.lp-footer-copy { font-size: 13.5px; color: var(--lp-muted); width: 100%; padding-top: 20px; border-top: 1px solid var(--line); }

/* Boot state */
.lp-boot { min-height: 70vh; display: grid; place-items: center; }
.lp-boot-msg { color: var(--lp-muted); font-size: 16px; }
.lp-boot-spin { width: 38px; height: 38px; border-radius: 50%; border: 3px solid var(--line);
    border-top-color: var(--accent); animation: lp-spin .8s linear infinite; }

/* Focus visibility (accessibility) */
.landing a:focus-visible, .landing button:focus-visible { outline: 2px solid var(--lp-amber); outline-offset: 2px; border-radius: 8px; }

/* ============================ Keyframes ============================ */
@keyframes lp-spin { to { transform: rotate(360deg); } }
@keyframes lp-draw { from { stroke-dashoffset: 320; } to { stroke-dashoffset: 0; } }
@keyframes lp-draw-long { to { stroke-dashoffset: 0; } }
@keyframes lp-drift1 { 0%, 100% { transform: translate(0, 0) scale(1); } 50% { transform: translate(-40px, 30px) scale(1.08); } }
@keyframes lp-drift2 { 0%, 100% { transform: translate(0, 0) scale(1); } 50% { transform: translate(50px, -30px) scale(1.12); } }
/* Two identical copies of the pills; shifting by half loops seamlessly. RTL
   content overflows to the left, so it travels the other way. */
@keyframes lp-marquee { from { transform: translateX(0); } to { transform: translateX(50%); } }
@keyframes lp-marquee-ltr { from { transform: translateX(0); } to { transform: translateX(-50%); } }

/* ============================ Responsive =========================== */
@media (max-width: 980px) {
    .lp-hero-grid { grid-template-columns: 1fr; }
    .lp-hero-copy { align-items: center; text-align: center; }
    .lp-hero-cta { justify-content: center; }
    .lp-groups, .lp-split, .lp-demo-grid, .lp-lead-grid { grid-template-columns: 1fr; }
    .lp-demo-grid .lp-demo-card { order: -1; }
    .lp-steps { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .lp-industries { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .lp-pricing-grid { grid-template-columns: 1fr; max-width: 460px; margin-inline: auto; }
}
@media (max-width: 820px) {
    .lp-links, .lp-cta-nav { display: none; }
    .lp-burger { display: grid; }
    .lp-drawer { display: block; position: fixed; z-index: 35; inset-block-start: 70px; inset-inline: 0;
        background: var(--card); border-bottom: 1px solid var(--line); padding: 16px 24px 24px;
        transform: translateY(-12px); opacity: 0; pointer-events: none; transition: transform .2s, opacity .2s;
        box-shadow: 0 24px 50px -30px rgba(42,30,20,.5); }
    .lp-drawer.open { transform: translateY(0); opacity: 1; pointer-events: auto; }
    .lp-drawer-links { display: flex; flex-direction: column; }
    .lp-drawer-links a { padding: 13px 8px; font-family: var(--font-display); font-weight: 700; font-size: 16px;
        color: var(--ink); text-decoration: none; border-bottom: 1px solid var(--line); }
    .lp-drawer-links a.active { color: var(--lp-amber); }
    .lp-drawer-actions { display: grid; gap: 10px; margin-top: 16px; }
    .lp-drawer-actions .btn { width: 100%; }
    .lp-why { grid-template-columns: 1fr; }
}
@media (max-width: 560px) {
    .lp-container { width: calc(100% - 32px); }
    .lp-steps { grid-template-columns: 1fr; }
    .lp-industries { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .lp-field-row { grid-template-columns: 1fr; }
    .lp-footer-inner { flex-direction: column; align-items: flex-start; }
    .lp-day li { flex-direction: column; gap: 2px; }
}
</style>
