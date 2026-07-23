<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@xorder/ui/i18n'
import XorderLogo from '@xorder/ui/XorderLogo.vue'
import Icon from '@xorder/ui/Icon.vue'
import { fetchLandingContent, postLead } from './lib/content.js'
import { track } from './lib/analytics.js'

const { t, locale } = useI18n()

// Admin-managed content (bilingual). Sections render once it has loaded.
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
    { id: 'home', key: 'landing.nav_home' },
    { id: 'features', key: 'landing.nav_features' },
    { id: 'how', key: 'landing.nav_how' },
    { id: 'packages', key: 'landing.nav_pricing' },
    { id: 'industries', key: 'landing.who_for' },
    { id: 'faq', key: 'landing.nav_faq' },
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
const demoSlug = computed(() => content.value?.demo?.restaurant_slug || 'mahsoub-restaurnt')
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
const heroWa = computed(() => content.value?.whatsapp?.hero_enabled !== false && !!waHref.value)

// ---- Packages ------------------------------------------------------------
const enabledPlans = computed(() => (content.value?.pricing?.plans || []).filter((p) => p.enabled !== false))
const planRecommended = (p) => p.recommended ?? p.popular ?? false
const billingPeriod = ref('monthly')
const planPrice = (p) => L(p[`price_${billingPeriod.value}`]) || L(p.price_label) || L(p.price)
const planHasPrice = (p) => !!planPrice(p)

// A missing demo restaurant makes the server-rendered QR 404; hide it cleanly
// rather than showing a broken-image icon (the brief: images must not break layout).
const demoQrOk = ref(true)

// ---- FAQ accordion -------------------------------------------------------
const enabledFaqs = computed(() => (content.value?.faq?.items || []).filter((f) => f.enabled !== false))
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
    submitting.value = true
    formErrors.value = {}
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
                    <XorderLogo class="lp-logo" />
                </a>

                <nav class="lp-links" :aria-label="t('app.title')">
                    <a v-for="item in NAV" :key="item.id" :href="`#${item.id}`"
                        :class="{ active: activeSection === item.id }"
                        :aria-current="activeSection === item.id ? 'true' : undefined"
                        @click="onNavClick(item.id)">{{ t(item.key) }}</a>
                </nav>

                <div class="lp-actions">
                    <a href="#lead" class="btn btn-accent lp-cta-nav" @click="onRequestDemo">
                        {{ L(content?.hero?.cta) || t('landing.get_started') }}
                    </a>
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
                    <a href="#lead" class="btn btn-accent lp-btn-lg" @click="onNavClick('home'); onRequestDemo()">
                        {{ L(content?.hero?.cta) || t('landing.get_started') }}
                    </a>
                </div>
            </div>
        </header>
        <div v-if="navOpen" class="lp-scrim" @click="closeNav" aria-hidden="true"></div>

        <main v-if="content">
            <!-- ============================ Hero ============================ -->
            <section id="home" class="lp-hero">
                <div class="lp-hero-blob lp-hero-blob-1" aria-hidden="true"></div>
                <div class="lp-hero-blob lp-hero-blob-2" aria-hidden="true"></div>
                <div class="lp-container lp-hero-inner">
                    <span class="lp-badge">{{ L(content.hero.badge) }}</span>
                    <h1 class="lp-h1">{{ L(content.hero.title) }}</h1>
                    <p class="lp-lead">{{ L(content.hero.sub) }}</p>

                    <div class="lp-hero-cta">
                        <a :href="heroPrimaryLink" class="btn btn-accent lp-btn-lg" @click="onRequestDemo">{{ L(content.hero.cta) }}</a>
                        <a :href="heroSecondaryLink" class="btn btn-ghost lp-btn-lg" @click="onViewDemo">{{ L(content.hero.secondary) }}</a>
                    </div>

                    <!-- Dashboard illustration (vector). Decorative abstract UI — food
                         emoji + bars + a trend chart — so nothing reads as real data. -->
                    <div class="lp-hero-figure">
                        <svg class="lp-dash-illus" viewBox="0 0 980 620" xmlns="http://www.w3.org/2000/svg"
                            role="img" :aria-label="t('landing.nav_qr_menu')">
                            <!-- main dashboard panel -->
                            <rect class="il-shadow" x="158" y="100" width="664" height="470" rx="26" />
                            <rect class="il-panel" x="150" y="88" width="664" height="470" rx="26" />

                            <!-- panel header: branch title + category pills -->
                            <rect class="il-bar-strong" x="678" y="120" width="118" height="12" rx="6" />
                            <rect class="il-bar-soft" x="706" y="140" width="90" height="8" rx="4" />
                            <rect class="il-pill-on" x="726" y="166" width="70" height="26" rx="13" />
                            <rect class="il-pill" x="644" y="166" width="70" height="26" rx="13" />
                            <rect class="il-pill" x="562" y="166" width="70" height="26" rx="13" />
                            <rect class="il-pill" x="480" y="166" width="70" height="26" rx="13" />

                            <!-- soft tint bands behind the grid -->
                            <rect class="il-band-a" x="176" y="214" width="300" height="60" rx="14" />
                            <rect class="il-band-b" x="488" y="214" width="300" height="60" rx="14" />

                            <!-- menu item cards (generic food emoji + abstract bars) -->
                            <g v-for="(em, i) in ['🍔','🌮','🥙','🧆']" :key="i" :transform="`translate(${644 - i * 162}, 300)`">
                                <rect class="il-card" x="0" y="0" width="150" height="224" rx="16" />
                                <text class="il-emoji" x="75" y="96" text-anchor="middle">{{ em }}</text>
                                <rect class="il-bar-strong" x="22" y="150" width="72" height="9" rx="4.5" />
                                <rect class="il-price" x="104" y="149" width="24" height="12" rx="6" />
                                <rect class="il-bar-soft" x="22" y="172" width="106" height="7" rx="3.5" />
                                <rect class="il-bar-soft" x="22" y="188" width="72" height="7" rx="3.5" />
                            </g>

                            <!-- floating: sales report + trend chart -->
                            <g>
                                <rect class="il-shadow" x="70" y="196" width="210" height="188" rx="20" />
                                <rect class="il-float" x="62" y="188" width="210" height="188" rx="20" />
                                <circle class="il-accent" cx="88" cy="216" r="8" />
                                <rect class="il-bar-soft" x="104" y="212" width="86" height="8" rx="4" />
                                <rect class="il-bar-strong" x="86" y="236" width="120" height="16" rx="6" />
                                <rect class="il-bar-soft" x="86" y="262" width="74" height="8" rx="4" />
                                <path class="il-chart-fill" d="M84 350 L106 338 L128 342 L150 322 L172 328 L194 304 L216 310 L238 286 L252 280 L252 360 L84 360 Z" />
                                <path class="il-chart-line" d="M84 350 L106 338 L128 342 L150 322 L172 328 L194 304 L216 310 L238 286 L252 280" />
                            </g>

                            <!-- floating: new order notification -->
                            <g>
                                <rect class="il-shadow" x="700" y="212" width="220" height="94" rx="16" />
                                <rect class="il-float" x="692" y="204" width="220" height="94" rx="16" />
                                <circle class="il-accent" cx="890" cy="230" r="6" />
                                <rect class="il-bar-strong" x="756" y="224" width="120" height="10" rx="5" />
                                <rect class="il-price" x="712" y="222" width="36" height="14" rx="7" />
                                <rect class="il-bar-soft" x="724" y="250" width="164" height="8" rx="4" />
                                <rect class="il-bar-soft" x="770" y="268" width="118" height="8" rx="4" />
                            </g>

                            <!-- floating: loyalty points -->
                            <g>
                                <rect class="il-shadow" x="686" y="452" width="222" height="140" rx="20" />
                                <rect class="il-float" x="678" y="444" width="222" height="140" rx="20" />
                                <text class="il-emoji-sm" x="716" y="490" text-anchor="middle">🥐</text>
                                <rect class="il-bar-soft" x="748" y="468" width="130" height="8" rx="4" />
                                <rect class="il-bar-strong" x="778" y="486" width="100" height="10" rx="5" />
                                <rect class="il-track" x="700" y="516" width="178" height="8" rx="4" />
                                <rect class="il-accent" x="700" y="516" width="112" height="8" rx="4" />
                                <rect class="il-accent" x="700" y="540" width="92" height="30" rx="10" />
                                <rect class="il-btn-label" x="720" y="552" width="52" height="8" rx="4" />
                            </g>
                        </svg>
                    </div>

                    <div class="lp-stats">
                        <div v-for="(p, i) in content.proof" :key="i">
                            <span class="lp-stat-num">{{ L(p.title) }}</span>
                            <span class="lp-stat-lbl">{{ L(p.text) }}</span>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ========================= Features ========================= -->
            <section id="features" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <span class="lp-eyebrow">{{ t('landing.nav_ordering') }}</span>
                        <h2 class="lp-h2">{{ L(content.features.title) }}</h2>
                        <p class="lp-sub">{{ L(content.features.sub) }}</p>
                    </div>
                    <div class="lp-feature-grid">
                        <div class="lp-feature" v-for="(f, i) in content.features.items" :key="i">
                            <span class="lp-feature-ico">{{ f.icon }}</span>
                            <h3 class="lp-feature-title">{{ L(f.title) }}</h3>
                            <p class="lp-feature-text">{{ L(f.text) }}</p>
                        </div>
                    </div>
                </div>
            </section>

            <!-- =================== How it works + Live demo ================ -->
            <section id="how" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <span class="lp-eyebrow">{{ t('landing.nav_how') }}</span>
                        <h2 class="lp-h2">{{ L(content.steps.title) }}</h2>
                    </div>
                    <ol class="lp-steps">
                        <li v-for="(s, i) in content.steps.items" :key="i" class="lp-step">
                            <span class="lp-step-num">{{ i + 1 }}</span>
                            <h3 class="lp-step-title">{{ L(s.title) }}</h3>
                            <p class="lp-step-text">{{ L(s.text) }}</p>
                        </li>
                    </ol>

                    <!-- Live demo, merged into the How-it-works section. -->
                    <div v-if="content.demo.enabled !== false" class="lp-demo-grid lp-how-demo">
                        <div class="lp-demo-card" :class="{ 'lp-demo-card-empty': !demoQrOk }">
                            <img v-show="demoQrOk" class="lp-qr-img" :src="demoQrUrl" width="200" height="200" alt="QR" loading="lazy" @error="demoQrOk = false" />
                            <div class="lp-demo-stand">{{ t('landing.demo_stand') }}</div>
                        </div>
                        <div class="lp-demo-copy">
                            <span class="lp-eyebrow">{{ t('landing.nav_demo') }}</span>
                            <h3 class="lp-demo-title">{{ L(content.demo.title) }}</h3>
                            <p class="lp-sub">{{ L(content.demo.text) }}</p>
                            <a :href="demoMenuUrl" target="_blank" rel="noopener" class="btn btn-accent lp-btn-lg" @click="onViewDemo">{{ L(content.demo.button) }}</a>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ========================= Packages ========================= -->
            <section id="packages" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <span class="lp-eyebrow">{{ t('landing.nav_pricing') }}</span>
                        <h2 class="lp-h2">{{ L(content.pricing.title) }}</h2>
                        <p class="lp-sub">{{ L(content.pricing.sub) }}</p>
                    </div>
                    <div v-if="content.pricing.billing" class="lp-billing">
                        <button type="button" class="lp-billing-opt" :class="{ on: billingPeriod === 'monthly' }"
                            @click="billingPeriod = 'monthly'">{{ L(content.pricing.billing.monthly) }}</button>
                        <button type="button" class="lp-billing-opt" :class="{ on: billingPeriod === 'yearly' }"
                            @click="billingPeriod = 'yearly'">
                            {{ L(content.pricing.billing.yearly) }}
                            <span v-if="L(content.pricing.billing.save)" class="lp-billing-save">{{ L(content.pricing.billing.save) }}</span>
                        </button>
                    </div>
                    <div class="lp-pricing-grid">
                        <div class="lp-plan" v-for="(plan, i) in enabledPlans" :key="i" :class="{ 'lp-plan-popular': planRecommended(plan) }">
                            <span v-if="planRecommended(plan)" class="lp-plan-badge">{{ L(content.pricing.popular_label) }}</span>
                            <h3 class="lp-plan-name">{{ L(plan.name) }}</h3>
                            <p class="lp-plan-note">{{ L(plan.subtitle) || L(plan.note) }}</p>
                            <div class="lp-plan-price">
                                <span v-if="planHasPrice(plan)" class="lp-plan-amount">{{ planPrice(plan) }}</span>
                                <span v-else class="lp-plan-amount">{{ t('landing.price_contact') }}</span>
                            </div>
                            <p v-if="!planHasPrice(plan)" class="lp-plan-note">{{ t('landing.price_contact_note') }}</p>
                            <ul class="lp-plan-feats">
                                <li v-for="(feat, fi) in plan.features" :key="fi"><span class="lp-check"><Icon name="check" :size="12" /></span>{{ L(feat) }}</li>
                            </ul>
                            <a href="#lead" class="btn lp-btn-lg lp-plan-cta" :class="planRecommended(plan) ? 'btn-accent' : 'btn-ghost'"
                                @click="onPackageCta(L(plan.name)); onRequestDemo()">
                                {{ L(plan.cta) || L(content.pricing.choose_label) }}
                            </a>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ======================== Industries ======================== -->
            <section id="industries" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <span class="lp-eyebrow">{{ t('landing.who_for') }}</span>
                        <h2 class="lp-h2">{{ L(content.industries.title) }}</h2>
                        <p class="lp-sub">{{ L(content.industries.sub) }}</p>
                    </div>
                    <div class="lp-industries">
                        <span class="lp-industry" v-for="(it, i) in content.industries.items" :key="i">
                            <span class="lp-industry-ic">{{ it.icon }}</span>{{ L(it.text) }}
                        </span>
                    </div>
                </div>
            </section>

            <!-- =========================== FAQ ============================ -->
            <section v-if="enabledFaqs.length" id="faq" class="lp-section">
                <div class="lp-container lp-faq-wrap">
                    <div class="lp-section-head">
                        <span class="lp-eyebrow">{{ t('landing.nav_faq') }}</span>
                        <h2 class="lp-h2">{{ L(content.faq.title) }}</h2>
                        <p class="lp-sub">{{ L(content.faq.sub) }}</p>
                    </div>
                    <div class="lp-faq">
                        <div class="lp-faq-item" v-for="(item, i) in enabledFaqs" :key="i" :class="{ open: openFaq === i }">
                            <h3 class="lp-faq-q">
                                <button type="button" :aria-expanded="openFaq === i" :aria-controls="`lp-faq-panel-${i}`"
                                    :id="`lp-faq-btn-${i}`" @click="toggleFaq(i)">
                                    <span>{{ L(item.q) }}</span>
                                    <Icon name="chevronDown" :size="18" class="lp-faq-chev" />
                                </button>
                            </h3>
                            <div :id="`lp-faq-panel-${i}`" role="region" :aria-labelledby="`lp-faq-btn-${i}`"
                                class="lp-faq-a" v-show="openFaq === i">
                                <p>{{ L(item.a) }}</p>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <!-- ========================= Lead form ======================== -->
            <section id="lead" class="lp-section lp-section-alt lp-lead-sec">
                <div class="lp-container lp-lead-grid">
                    <div class="lp-lead-copy">
                        <h2 class="lp-h2">{{ L(content.lead_form.title) }}</h2>
                        <p class="lp-sub">{{ L(content.lead_form.sub) }}</p>
                        <a v-if="heroWa" :href="waHref" target="_blank" rel="noopener" class="lp-hero-wa" @click="onWhatsapp">
                            <span class="lp-wa-ic">✆</span>{{ L(content.hero.whatsapp_label) }}
                        </a>
                        <a v-if="content.contact.email" :href="`mailto:${content.contact.email}`" class="lp-lead-email">{{ content.contact.email }}</a>
                    </div>

                    <div class="lp-lead-card">
                        <div v-if="submitted" class="lp-lead-done">
                            <span class="lp-lead-done-ic"><Icon name="check" :size="26" /></span>
                            <p>{{ L(content.lead_form.success) }}</p>
                        </div>
                        <form v-else class="lp-form" @submit.prevent="submitLead">
                            <!-- Honeypot: off-screen, skipped by keyboard/screen readers; bots auto-fill it. -->
                            <input v-model="form.website" type="text" name="website" tabindex="-1" autocomplete="off"
                                aria-hidden="true"
                                style="position:absolute;inset-inline-start:-9999px;height:0;width:0;opacity:0;pointer-events:none;" />
                            <label class="lp-field">
                                <span>{{ t('landing.lead_restaurant') }} *</span>
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
                                    <input v-model="form.whatsapp" required maxlength="40" dir="ltr" placeholder="+20…" />
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
                                <textarea v-model="form.message" rows="3" maxlength="2000"></textarea>
                            </label>
                            <p v-if="formErrors._" class="lp-err">{{ formErrors._[0] }}</p>
                            <button type="submit" class="btn btn-accent lp-btn-lg lp-form-submit" :disabled="submitting">
                                {{ submitting ? t('landing.lead_sending') : L(content.lead_form.button) }}
                            </button>
                        </form>
                    </div>
                </div>
            </section>

            <!-- ========================== Footer ========================== -->
            <footer class="lp-footer">
                <div class="lp-container lp-footer-inner">
                    <div class="lp-footer-brand">
                        <XorderLogo class="lp-logo-footer" />
                        <div class="lp-footer-tag">{{ L(content.footer.tagline) }}</div>
                    </div>
                    <nav class="lp-footer-links" :aria-label="t('app.title')">
                        <a v-for="item in NAV" :key="item.id" :href="`#${item.id}`" @click="onNavClick(item.id)">{{ t(item.key) }}</a>
                    </nav>
                    <div class="lp-footer-copy">© {{ year }} {{ t('app.title') }}. {{ L(content.footer.rights) }}</div>
                </div>
            </footer>
        </main>

        <!-- Floating WhatsApp -->
        <a v-if="content && floatingWa" :href="waHref" target="_blank" rel="noopener" class="lp-wa-float"
            :aria-label="L(content.hero.whatsapp_label)" @click="onWhatsapp">✆</a>

        <!-- Loading / error states -->
        <div v-if="!content" class="lp-boot">
            <p v-if="loadError" class="lp-boot-msg">{{ t('landing.lead_error') }}</p>
            <div v-else class="lp-boot-spin" role="status" :aria-label="t('common.saving')"></div>
        </div>
    </div>
</template>

<style scoped>
.landing { background: var(--page); color: var(--body); min-height: 100vh; }
/* Full-bleed sections; a centered container caps the readable width. */
.lp-container { width: min(calc(100% - 48px), 1200px); margin-inline: auto; }

/* ============================== Header ============================== */
.lp-header { position: sticky; top: 0; z-index: 40; transition: background .2s, border-color .2s, box-shadow .2s;
    background: color-mix(in srgb, var(--page) 82%, transparent); backdrop-filter: blur(12px);
    border-bottom: 1px solid transparent; }
.lp-header.is-scrolled { border-bottom-color: var(--line); box-shadow: 0 6px 24px -20px rgba(42,30,20,.5); }
.lp-nav { display: flex; align-items: center; justify-content: space-between; height: 70px; gap: 20px; }
.lp-brand { display: flex; align-items: center; text-decoration: none; flex: none; }
.lp-logo { height: 30px; width: auto; color: var(--ink); display: block; }
.lp-links { display: flex; gap: 6px; margin-inline-start: auto; }
.lp-links a { color: var(--body); font-size: 15.5px; text-decoration: none; padding: 8px 12px; border-radius: 9px;
    transition: color .15s, background .15s; }
.lp-links a:hover { color: var(--accent); background: var(--accent-soft); }
.lp-links a.active { color: var(--accent); font-weight: 600; }
.lp-actions { display: flex; align-items: center; gap: 10px; flex: none; }
.lp-lang { width: 40px; height: 40px; border-radius: 10px; display: grid; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--muted); transition: background .15s, color .15s; }
.lp-lang:hover { background: var(--accent-soft); color: var(--accent); }
.lp-cta-nav { padding: 10px 18px; }
.lp-burger { display: none; width: 42px; height: 42px; border-radius: 10px; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--ink); }

/* Mobile drawer */
.lp-drawer { display: none; }
.lp-scrim { position: fixed; inset: 0; z-index: 30; background: rgba(20,14,8,.4); backdrop-filter: blur(2px); }

/* ============================== Buttons ============================= */
.lp-btn-lg { padding: 13px 26px; font-size: 16px; }

/* =============================== Hero ============================== */
.lp-hero { position: relative; min-height: 100svh; display: flex; flex-direction: column; justify-content: center;
    padding: clamp(80px, 9vh, 100px) 0 clamp(24px, 4vh, 44px); overflow: hidden; }
.lp-hero-blob { position: absolute; border-radius: 50%; filter: blur(70px); opacity: .55; z-index: 0; pointer-events: none; }
.lp-hero-blob-1 { width: 460px; height: 460px; inset-inline-end: -120px; top: -140px;
    background: radial-gradient(circle, var(--accent-soft), transparent 70%); }
.lp-hero-blob-2 { width: 360px; height: 360px; inset-inline-start: -140px; bottom: -160px;
    background: radial-gradient(circle, var(--green-soft), transparent 70%); }
.lp-hero-inner { position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; text-align: center; }
.lp-badge { display: inline-block; background: var(--card); color: var(--accent); border: 1px solid var(--accent-soft);
    font-size: 13px; font-weight: 600; padding: 7px 14px; border-radius: 20px; font-family: var(--font-display);
    box-shadow: 0 2px 10px -6px rgba(42,30,20,.3); }
.lp-h1 { font-family: var(--font-display); font-weight: 800; font-size: clamp(32px, 5vw, 52px); line-height: 1.08;
    color: var(--ink); margin: 18px 0 0; letter-spacing: -0.02em; }
.lp-lead { font-size: clamp(16px, 2vw, 19px); line-height: 1.62; color: var(--body); margin: 18px auto 0; max-width: 40em; }
.lp-hero-cta { display: flex; gap: 12px; margin-top: 26px; flex-wrap: wrap; justify-content: center; }
.lp-hero-wa { display: inline-flex; align-items: center; gap: 8px; margin-top: 16px; color: var(--green);
    font-weight: 600; font-size: 15.5px; text-decoration: none; }
.lp-hero-wa:hover { text-decoration: underline; }
.lp-wa-ic { display: grid; place-items: center; width: 26px; height: 26px; border-radius: 50%;
    background: var(--green); color: #fff; font-size: 14px; }
.lp-stats { display: flex; gap: 18px 48px; margin: clamp(14px, 2.2vh, 26px) auto 0; flex-wrap: wrap; justify-content: center;
    padding-top: clamp(14px, 2vh, 22px); border-top: 1px solid var(--line); max-width: 760px; width: 100%; }
.lp-stats > div { display: flex; flex-direction: column; min-width: 96px; align-items: center; }
.lp-stat-num { font-family: var(--font-display); font-weight: 800; font-size: 27px; color: var(--ink); }
.lp-stat-lbl { font-size: 14px; color: var(--muted); margin-top: 2px; }

/* Dashboard illustration (vector) */
.lp-hero-figure { width: 100%; margin-top: clamp(12px, 2vh, 24px); display: flex; justify-content: center; }
.lp-dash-illus { width: 100%; max-width: 920px; max-height: 38vh; height: auto; display: block;
    filter: drop-shadow(0 40px 80px rgba(42,30,20,.16)); }
.il-shadow { fill: rgba(42,30,20,.10); }
.il-panel { fill: var(--card); stroke: var(--line); stroke-width: 1.5; }
.il-float { fill: var(--card); stroke: var(--line); stroke-width: 1.5; }
.il-card { fill: var(--page); stroke: var(--line); stroke-width: 1.5; }
.il-accent { fill: var(--accent); }
.il-bar-strong { fill: var(--ink); opacity: .8; }
.il-bar-soft { fill: var(--muted); opacity: .4; }
.il-pill-on { fill: var(--ink); }
.il-pill { fill: var(--accent-soft); }
.il-band-a { fill: var(--accent-soft); opacity: .7; }
.il-band-b { fill: var(--green-soft); opacity: .7; }
.il-price { fill: var(--accent); opacity: .85; }
.il-track { fill: var(--line); }
.il-btn-label { fill: #fff; opacity: .92; }
.il-chart-fill { fill: var(--green-soft); }
.il-chart-line { fill: none; stroke: var(--green); stroke-width: 3; stroke-linecap: round; stroke-linejoin: round; }
.il-emoji { font-size: 46px; }
.il-emoji-sm { font-size: 30px; }

/* ============================= Sections ============================ */
.lp-section { min-height: 100svh; display: flex; flex-direction: column; justify-content: center;
    padding: clamp(64px, 9vh, 104px) 0; scroll-margin-top: 80px; }
.lp-section-alt { background: color-mix(in srgb, var(--accent-soft) 55%, var(--page)); }
.lp-section-head { text-align: center; max-width: 44em; margin: 0 auto clamp(36px, 5vw, 56px); }
.lp-eyebrow { display: inline-block; font-family: var(--font-display); font-weight: 700; font-size: 13px;
    letter-spacing: .06em; text-transform: uppercase; color: var(--accent); margin-bottom: 12px; }
.lp-h2 { font-family: var(--font-display); font-weight: 800; font-size: clamp(26px, 4vw, 38px); color: var(--ink); letter-spacing: -0.01em; line-height: 1.15; }
.lp-sub { font-size: clamp(15px, 2vw, 18px); color: var(--muted); margin-top: 12px; line-height: 1.6; }

/* Showcase (text + list) */
.lp-showcase { display: grid; grid-template-columns: 1fr 1fr; gap: clamp(28px, 5vw, 64px); align-items: center; }
.lp-showcase-copy .lp-sub { max-width: 30em; }
.lp-showcase-list { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; }
.lp-showcase-list li { display: flex; align-items: center; gap: 14px; background: var(--card); border: 1px solid var(--line);
    border-radius: 14px; padding: 15px 18px; box-shadow: 0 2px 14px -12px rgba(42,30,20,.4); }
.lp-offer-ic { display: grid; place-items: center; width: 42px; height: 42px; border-radius: 12px; flex-shrink: 0;
    background: var(--accent-soft); color: var(--accent); font-size: 20px; }
.lp-offer-text { font-size: 16px; font-weight: 600; color: var(--ink); }

/* Problem / solution */
.lp-problem-grid { display: grid; grid-template-columns: 1.1fr .9fr; gap: 28px; align-items: start; }
.lp-problem-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 12px; }
.lp-problem-list li { display: flex; align-items: flex-start; gap: 12px; background: var(--card); border: 1px solid var(--line);
    border-radius: 13px; padding: 15px 17px; font-size: 16px; color: var(--body); }
.lp-x { display: grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    background: var(--red-soft); color: var(--red); font-size: 12px; font-weight: 700; margin-top: 1px; }
.lp-solution { padding: 28px; border-radius: 18px; background: var(--card); border: 1px solid var(--accent);
    box-shadow: 0 24px 50px -34px rgba(248,154,6,.5); }
.lp-solution-badge { display: inline-block; background: var(--accent); color: #fff; font-family: var(--font-display);
    font-weight: 600; font-size: 12.5px; padding: 4px 12px; border-radius: 16px; }
.lp-solution-title { font-family: var(--font-display); font-weight: 800; font-size: 23px; color: var(--ink); margin: 14px 0 8px; }
.lp-solution-text { font-size: 16.5px; line-height: 1.6; color: var(--body); }

/* Features grid */
.lp-feature-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
.lp-feature { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 26px 24px;
    transition: transform .18s, box-shadow .18s, border-color .18s; }
.lp-feature:hover { transform: translateY(-3px); box-shadow: 0 24px 50px -34px rgba(42,30,20,.5); border-color: var(--accent-soft); }
.lp-feature-ico { display: grid; place-items: center; width: 50px; height: 50px; border-radius: 14px;
    background: var(--accent-soft); font-size: 24px; }
.lp-feature-title { font-family: var(--font-display); font-weight: 700; font-size: 18px; color: var(--ink); margin: 16px 0 7px; }
.lp-feature-text { font-size: 15px; line-height: 1.58; color: var(--muted); }

/* Compare */
.lp-compare { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; max-width: 900px; margin: 0 auto; }
.lp-compare-col { border-radius: 18px; padding: 28px; }
.lp-compare-col ul { list-style: none; padding: 0; margin: 16px 0 0; display: flex; flex-direction: column; gap: 12px; }
.lp-compare-col li { display: flex; align-items: flex-start; gap: 10px; font-size: 15.5px; }
.lp-compare-title { font-family: var(--font-display); font-weight: 700; font-size: 18px; color: var(--ink); }
.lp-compare-them { background: var(--card); border: 1px solid var(--line); }
.lp-compare-them li { color: var(--muted); }
.lp-compare-us { background: var(--ink); border: 1px solid var(--ink); }
.lp-compare-us .lp-compare-title, .lp-compare-us li { color: #fff; }
.lp-check { display: grid; place-items: center; width: 20px; height: 20px; border-radius: 50%; flex-shrink: 0;
    background: var(--green); color: #fff; margin-top: 1px; }

/* How it works */
.lp-steps { list-style: none; padding: 0; margin: 0; display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
.lp-step { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 28px 24px; }
.lp-step-num { display: grid; place-items: center; width: 46px; height: 46px; border-radius: 14px; background: var(--accent);
    color: #fff; font-family: var(--font-display); font-weight: 800; font-size: 20px; }
.lp-step-title { font-family: var(--font-display); font-weight: 700; font-size: 18px; color: var(--ink); margin: 18px 0 7px; }
.lp-step-text { font-size: 15px; line-height: 1.58; color: var(--muted); }

/* Demo */
.lp-demo-grid { display: grid; grid-template-columns: .8fr 1.2fr; gap: clamp(28px, 5vw, 60px); align-items: center; }
.lp-demo-card { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 28px; text-align: center;
    box-shadow: 0 30px 60px -40px rgba(42,30,20,.5); justify-self: center; max-width: 320px; }
.lp-qr-img { width: 100%; max-width: 220px; height: auto; border-radius: 12px; }
.lp-demo-stand { margin-top: 14px; font-family: var(--font-display); font-weight: 600; color: var(--muted); font-size: 14px; }
.lp-how-demo { margin-top: clamp(40px, 6vh, 72px); padding-top: clamp(32px, 4vh, 48px); border-top: 1px solid var(--line); }
.lp-demo-title { font-family: var(--font-display); font-weight: 800; font-size: clamp(22px, 3vw, 30px); color: var(--ink); margin-top: 6px; }
.lp-demo-copy .btn { margin-top: 22px; }

/* Pricing */
.lp-billing { display: flex; width: fit-content; gap: 4px; padding: 5px; background: var(--card); border: 1px solid var(--line);
    border-radius: 14px; margin: 0 auto clamp(32px, 4vw, 44px); }
.lp-billing-opt { border: none; background: none; cursor: pointer; font-family: var(--font-display); font-weight: 600;
    font-size: 15px; color: var(--muted); padding: 9px 20px; border-radius: 10px; display: inline-flex; align-items: center; gap: 8px; }
.lp-billing-opt.on { background: var(--accent); color: #fff; }
.lp-billing-save { font-size: 11.5px; font-weight: 700; background: var(--green-soft); color: var(--green); padding: 2px 8px; border-radius: 10px; }
.lp-billing-opt.on .lp-billing-save { background: rgba(255,255,255,.25); color: #fff; }
.lp-pricing-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; align-items: stretch; }
.lp-plan { position: relative; background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 30px 26px;
    display: flex; flex-direction: column; }
.lp-plan-popular { border-color: var(--accent); box-shadow: 0 30px 60px -38px rgba(248,154,6,.6); }
.lp-plan-badge { position: absolute; top: -12px; inset-inline-start: 26px; background: var(--accent); color: #fff;
    font-family: var(--font-display); font-weight: 700; font-size: 12px; padding: 5px 13px; border-radius: 20px; }
.lp-plan-name { font-family: var(--font-display); font-weight: 800; font-size: 21px; color: var(--ink); }
.lp-plan-note { font-size: 14px; color: var(--muted); margin-top: 6px; line-height: 1.5; }
.lp-plan-price { margin: 18px 0; }
.lp-plan-amount { font-family: var(--font-display); font-weight: 800; font-size: 30px; color: var(--ink); }
.lp-plan-feats { list-style: none; padding: 0; margin: 6px 0 22px; display: flex; flex-direction: column; gap: 11px; flex: 1; }
.lp-plan-feats li { display: flex; align-items: flex-start; gap: 10px; font-size: 15px; color: var(--body); }
.lp-plan-cta { width: 100%; justify-content: center; }

/* Industries */
.lp-industries { display: flex; flex-wrap: wrap; justify-content: center; gap: 12px; max-width: 860px; margin: 0 auto; }
.lp-industry { display: inline-flex; align-items: center; gap: 10px; background: var(--card); border: 1px solid var(--line);
    border-radius: 40px; padding: 11px 20px; font-family: var(--font-display); font-weight: 600; color: var(--ink); font-size: 15.5px; }
.lp-industry-ic { font-size: 20px; }

/* FAQ */
.lp-faq-wrap { max-width: 820px; }
.lp-faq { display: flex; flex-direction: column; gap: 12px; }
.lp-faq-item { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; transition: border-color .15s; }
.lp-faq-item.open { border-color: var(--accent); }
.lp-faq-q { margin: 0; }
.lp-faq-q button { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 16px;
    background: none; border: none; cursor: pointer; text-align: start; padding: 18px 20px;
    font-family: var(--font-display); font-weight: 600; font-size: 16.5px; color: var(--ink); }
.lp-faq-chev { color: var(--muted); flex-shrink: 0; transition: transform .2s; }
.lp-faq-item.open .lp-faq-chev { transform: rotate(180deg); color: var(--accent); }
.lp-faq-a { padding: 0 20px 20px; }
.lp-faq-a p { margin: 0; font-size: 15.5px; line-height: 1.65; color: var(--body); }

/* Lead form */
.lp-lead-grid { display: grid; grid-template-columns: 1fr 1.1fr; gap: clamp(28px, 5vw, 56px); align-items: center; }
.lp-lead-copy .lp-sub { max-width: 30em; }
.lp-lead-email { display: inline-block; margin-top: 12px; color: var(--muted); font-size: 15px; text-decoration: none; }
.lp-lead-email:hover { color: var(--ink); text-decoration: underline; }
.lp-lead-card { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: clamp(22px, 3vw, 32px);
    box-shadow: 0 30px 60px -42px rgba(42,30,20,.5); }
.lp-form { display: flex; flex-direction: column; gap: 15px; }
.lp-field { display: flex; flex-direction: column; gap: 6px; }
.lp-field > span { font-family: var(--font-display); font-weight: 600; font-size: 14px; color: var(--ink); }
.lp-field input, .lp-field select, .lp-field textarea { width: 100%; padding: 11px 13px; border: 1px solid var(--line);
    border-radius: 11px; background: var(--page); color: var(--ink); font-size: 15px; font-family: inherit; transition: border-color .15s, box-shadow .15s; }
.lp-field input:focus, .lp-field select:focus, .lp-field textarea:focus { outline: none; border-color: var(--accent);
    box-shadow: 0 0 0 3px var(--accent-soft); }
.lp-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
.lp-err { color: var(--red); font-size: 13px; }
.lp-form-submit { margin-top: 4px; }
.lp-lead-done { text-align: center; padding: 40px 20px; display: flex; flex-direction: column; align-items: center; gap: 16px; }
.lp-lead-done-ic { display: grid; place-items: center; width: 60px; height: 60px; border-radius: 50%; background: var(--green-soft); color: var(--green); }
.lp-lead-done p { font-size: 17px; color: var(--ink); font-weight: 600; max-width: 22em; }

/* Footer */
.lp-footer { background: var(--page); border-top: 1px solid var(--line); padding: 44px 0; }
.lp-footer-inner { display: flex; align-items: center; justify-content: space-between; gap: 24px; flex-wrap: wrap; }
.lp-footer-brand { display: flex; flex-direction: column; gap: 10px; }
.lp-logo-footer { height: 28px; width: auto; color: var(--ink); }
.lp-footer-tag { font-size: 14px; color: var(--muted); max-width: 26em; }
.lp-footer-links { display: flex; flex-wrap: wrap; gap: 8px 20px; }
.lp-footer-links a { color: var(--body); font-size: 14.5px; text-decoration: none; }
.lp-footer-links a:hover { color: var(--accent); }
.lp-footer-copy { font-size: 13.5px; color: var(--muted); width: 100%; padding-top: 20px; border-top: 1px solid var(--line); }

/* Floating WhatsApp */
.lp-wa-float { position: fixed; inset-block-end: 22px; inset-inline-end: 22px; z-index: 45; width: 54px; height: 54px;
    border-radius: 50%; background: var(--green); color: #fff; display: grid; place-items: center; font-size: 24px;
    text-decoration: none; box-shadow: 0 16px 36px -14px rgba(31,122,61,.7); transition: transform .15s; }
.lp-wa-float:hover { transform: scale(1.06); }

/* Boot state */
.lp-boot { min-height: 70vh; display: grid; place-items: center; }
.lp-boot-msg { color: var(--muted); font-size: 16px; }
.lp-boot-spin { width: 38px; height: 38px; border-radius: 50%; border: 3px solid var(--line);
    border-top-color: var(--accent); animation: lp-spin .8s linear infinite; }
@keyframes lp-spin { to { transform: rotate(360deg); } }

/* Focus visibility (accessibility) */
.landing a:focus-visible, .landing button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 8px; }

/* ============================ Responsive =========================== */
@media (max-width: 980px) {
    .lp-showcase, .lp-problem-grid, .lp-compare, .lp-demo-grid, .lp-lead-grid { grid-template-columns: 1fr; }
    .lp-demo-grid .lp-demo-card { order: -1; }
    .lp-feature-grid, .lp-steps { grid-template-columns: repeat(2, 1fr); }
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
    .lp-drawer-links a { padding: 13px 8px; font-family: var(--font-display); font-weight: 600; font-size: 16px;
        color: var(--ink); text-decoration: none; border-bottom: 1px solid var(--line); }
    .lp-drawer-links a.active { color: var(--accent); }
    .lp-drawer-actions { display: grid; gap: 10px; margin-top: 16px; }
    .lp-drawer-actions .btn { width: 100%; justify-content: center; }
}
@media (max-width: 560px) {
    .lp-container { width: calc(100% - 32px); }
    .lp-feature-grid, .lp-steps { grid-template-columns: 1fr; }
    .lp-field-row { grid-template-columns: 1fr; }
    .lp-footer-inner { flex-direction: column; align-items: flex-start; }
    .lp-hero-qr { inset-inline-start: 50%; transform: translateX(-50%); inset-block-end: -18px; }
    .lp-phone { width: 260px; height: 522px; }
}
</style>
