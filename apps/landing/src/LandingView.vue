<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue'
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

onMounted(async () => {
    try {
        content.value = await fetchLandingContent()
        applySeo(content.value.seo)
    } catch {
        loadError.value = true
    }
})

// Keep the document title/meta in sync if the language changes after load.
watch(locale, () => { if (content.value) applySeo(content.value.seo) })

// Pick the active locale from a bilingual { en, ar } field.
const L = (field) => (field && (field[locale.value] ?? field.en)) || ''

function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
const targetLocaleKey = () => locale.value === 'ar' ? 'languages.en' : 'languages.ar'
const targetLocaleAriaKey = () => locale.value === 'ar' ? 'common.switch_to_english' : 'common.switch_to_arabic'

// ---- Derived links -------------------------------------------------------
const demoSlug = computed(() => content.value?.demo?.restaurant_slug || 'xorderrest')
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
// Billing period toggle: monthly ⇄ yearly. Falls back to the single price_label
// for plans (or admin rows) that don't define per-period prices.
const billingPeriod = ref('monthly')
const planPrice = (p) => L(p[`price_${billingPeriod.value}`]) || L(p.price_label) || L(p.price)

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
    const pick = (f) => (f && typeof f === 'object') ? L(f) : f
    const title = pick(seo.title)
    const description = pick(seo.description)
    if (title) document.title = title
    setMeta('name', 'description', description)
    setMeta('property', 'og:title', pick(seo.og_title) || title)
    setMeta('property', 'og:description', pick(seo.og_description) || description)
    setMeta('property', 'og:type', 'website')
    if (seo.og_image) setMeta('property', 'og:image', seo.og_image)
}
</script>

<template>
    <div class="theme-warm landing">
        <!-- Header -->
        <header class="lp-header">
            <div class="lp-container lp-nav">
                <a href="/" class="lp-brand">
                    <XorderLogo class="lp-logo" />
                </a>

                <nav class="lp-links">
                    <a href="#offer">{{ t('landing.nav_qr_menu') }}</a>
                    <a href="#features">{{ t('landing.nav_ordering') }}</a>
                    <a href="#no-commission">{{ t('landing.nav_no_commission') }}</a>
                    <a href="#packages">{{ t('landing.nav_pricing') }}</a>
                </nav>

                <div class="lp-actions">
                    <a href="#lead" class="btn btn-accent" @click="onRequestDemo">{{ L(content?.hero?.cta) || t('landing.get_started') }}</a>
                    <button class="lp-lang" @click="toggleLang"
                        :title="t(targetLocaleKey())"
                        :aria-label="t(targetLocaleAriaKey())">
                        <Icon name="globe" :size="21" />
                    </button>
                </div>
            </div>
        </header>

        <main v-if="content">
            <!-- Hero -->
            <section class="lp-hero">
                <div class="lp-container lp-hero-grid">
                    <div class="lp-hero-copy">
                        <span class="lp-badge">{{ L(content.hero.badge) }}</span>
                        <h1 class="lp-h1">{{ L(content.hero.title) }}</h1>
                        <p class="lp-lead">{{ L(content.hero.sub) }}</p>

                        <ul class="lp-trust">
                            <li v-for="(v, i) in (content.hero.value_points || [content.hero.no_commission_label, content.hero.ready_label])" :key="i">
                                <span class="lp-trust-ic">✓</span>{{ L(v) }}
                            </li>
                        </ul>

                        <div class="lp-hero-cta">
                            <a :href="heroPrimaryLink" class="btn btn-accent lp-btn-lg" @click="onRequestDemo">{{ L(content.hero.cta) }}</a>
                            <a :href="heroSecondaryLink" class="btn btn-ghost lp-btn-lg" @click="onViewDemo">{{ L(content.hero.secondary) }}</a>
                        </div>
                        <a v-if="heroWa" :href="waHref" target="_blank" rel="noopener" class="lp-hero-wa" @click="onWhatsapp">
                            <span class="lp-wa-ic">✆</span>{{ L(content.hero.whatsapp_label) }}
                        </a>

                        <div class="lp-stats">
                            <div v-for="(p, i) in content.proof" :key="i">
                                <span class="lp-stat-num">{{ L(p.title) }}</span>
                                <span class="lp-stat-lbl">{{ L(p.text) }}</span>
                            </div>
                        </div>
                    </div>

                    <!-- Phone mockup + QR -->
                    <div class="lp-hero-art">
                        <div class="lp-phone">
                            <div class="lp-phone-notch"></div>
                            <div class="lp-phone-screen">
                                <div class="lp-menu-head">
                                    <div class="lp-menu-logo">Q</div>
                                    <div>
                                        <div class="lp-menu-name">{{ t('landing.demo_name') }}</div>
                                        <div class="lp-menu-tag">{{ t('landing.demo_tag') }}</div>
                                    </div>
                                </div>
                                <div class="lp-menu-cats">
                                    <span class="lp-chip lp-chip-on">{{ t('landing.demo_cat_mains') }}</span>
                                    <span class="lp-chip">{{ t('landing.demo_cat_starters') }}</span>
                                    <span class="lp-chip">{{ t('landing.demo_cat_drinks') }}</span>
                                </div>
                                <div class="lp-menu-item" v-for="i in 3" :key="i">
                                    <div class="lp-menu-thumb"></div>
                                    <div class="lp-menu-meta">
                                        <div class="lp-menu-itemname">{{ t('landing.demo_item') }}</div>
                                        <div class="lp-menu-desc">{{ t('landing.demo_desc') }}</div>
                                    </div>
                                    <div class="lp-menu-price">85</div>
                                </div>
                                <div class="lp-menu-order">{{ t('landing.demo_order') }}</div>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Offer -->
            <section id="offer" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.offer.title) }}</h2>
                        <p class="lp-sub">{{ L(content.offer.text) }}</p>
                    </div>
                    <div class="lp-offer-grid">
                        <div class="lp-offer-item" v-for="(it, i) in content.offer.items" :key="i">
                            <span class="lp-offer-ic">{{ it.icon }}</span>
                            <span class="lp-offer-text">{{ L(it.text) }}</span>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Problem / Solution -->
            <section id="problem" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.problem.title) }}</h2>
                        <p class="lp-sub">{{ L(content.problem.sub) }}</p>
                    </div>
                    <div class="lp-problem-grid">
                        <ul class="lp-problem-list">
                            <li v-for="(p, i) in content.problem.problems" :key="i">
                                <span class="lp-x">✕</span>{{ L(p.text) }}
                            </li>
                        </ul>
                        <div class="lp-solution card">
                            <span class="lp-solution-badge">{{ t('landing.solution') }}</span>
                            <h3 class="lp-solution-title">{{ L(content.problem.solution_title) }}</h3>
                            <p class="lp-solution-text">{{ L(content.problem.solution_text) }}</p>
                        </div>
                    </div>
                </div>
            </section>

            <!-- No commission -->
            <section id="no-commission" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.no_commission.title) }}</h2>
                        <p class="lp-sub">{{ L(content.no_commission.text) }}</p>
                    </div>
                    <div class="lp-compare">
                        <div class="lp-compare-col lp-compare-them">
                            <h3 class="lp-compare-title">{{ L(content.no_commission.third_party_title) }}</h3>
                            <ul>
                                <li v-for="(it, i) in content.no_commission.third_party" :key="i"><span class="lp-x">✕</span>{{ L(it.text) }}</li>
                            </ul>
                        </div>
                        <div class="lp-compare-col lp-compare-us">
                            <h3 class="lp-compare-title">{{ L(content.no_commission.xorder_title) }}</h3>
                            <ul>
                                <li v-for="(it, i) in content.no_commission.xorder" :key="i"><span class="lp-check">✓</span>{{ L(it.text) }}</li>
                            </ul>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Features -->
            <section id="features" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.features.title) }}</h2>
                        <p class="lp-sub">{{ L(content.features.sub) }}</p>
                    </div>
                    <div class="lp-feature-grid">
                        <div class="lp-feature card" v-for="(f, i) in content.features.items" :key="i">
                            <span class="lp-feature-ico">{{ f.icon }}</span>
                            <h3 class="lp-feature-title">{{ L(f.title) }}</h3>
                            <p class="lp-feature-text">{{ L(f.text) }}</p>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Demo -->
            <section v-if="content.demo.enabled !== false" id="demo" class="lp-section">
                <div class="lp-container lp-demo-grid">
                    <div>
                        <h2 class="lp-h2">{{ L(content.demo.title) }}</h2>
                        <p class="lp-sub lp-demo-sub">{{ L(content.demo.text) }}</p>
                        <ol class="lp-flow">
                            <li v-for="(s, i) in content.steps.items" :key="i">
                                <span class="lp-flow-num">{{ i + 1 }}</span>
                                <span>
                                    <span class="lp-flow-title">{{ L(s.title) }}</span>
                                    <span class="lp-flow-text">{{ L(s.text) }}</span>
                                </span>
                            </li>
                        </ol>
                        <a :href="demoMenuUrl" target="_blank" rel="noopener" class="btn btn-accent lp-btn-lg" @click="onViewDemo">{{ L(content.demo.button) }}</a>
                    </div>
                    <div class="lp-demo-card card">
                        <img class="lp-qr-img" :src="demoQrUrl" width="200" height="200"
                            alt="QR" loading="lazy" />
                        <div class="lp-demo-stand">{{ t('landing.demo_stand') }}</div>
                    </div>
                </div>
            </section>

            <!-- Packages -->
            <section id="packages" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head">
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
                        <div class="lp-plan card" v-for="(plan, i) in enabledPlans" :key="i" :class="{ 'lp-plan-popular': planRecommended(plan) }">
                            <span v-if="planRecommended(plan)" class="lp-plan-badge">{{ L(content.pricing.popular_label) }}</span>
                            <h3 class="lp-plan-name">{{ L(plan.name) }}</h3>
                            <p class="lp-plan-note">{{ L(plan.subtitle) || L(plan.note) }}</p>
                            <div class="lp-plan-price">
                                <span class="lp-plan-amount">{{ planPrice(plan) }}</span>
                            </div>
                            <ul class="lp-plan-feats">
                                <li v-for="(feat, fi) in plan.features" :key="fi">{{ L(feat) }}</li>
                            </ul>
                            <a href="#lead" class="btn lp-btn-lg" :class="planRecommended(plan) ? 'btn-accent' : 'btn-ghost'"
                                @click="onPackageCta(L(plan.name)); onRequestDemo()">
                                {{ L(plan.cta) || L(content.pricing.choose_label) }}
                            </a>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Industries -->
            <section id="industries" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
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

            <!-- Lead form -->
            <section id="lead" class="lp-section lp-section-alt lp-lead-sec">
                <div class="lp-container lp-lead-grid">
                    <div class="lp-lead-copy">
                        <h2 class="lp-h2">{{ L(content.lead_form.title) }}</h2>
                        <p class="lp-sub">{{ L(content.lead_form.sub) }}</p>
                        <a v-if="heroWa" :href="waHref" target="_blank" rel="noopener" class="lp-hero-wa" @click="onWhatsapp">
                            <span class="lp-wa-ic">✆</span>{{ L(content.hero.whatsapp_label) }}
                        </a>
                    </div>

                    <div class="lp-lead-card card">
                        <div v-if="submitted" class="lp-lead-done">
                            <span class="lp-lead-done-ic">✓</span>
                            <p>{{ L(content.lead_form.success) }}</p>
                        </div>
                        <form v-else class="lp-form" @submit.prevent="submitLead">
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

            <!-- Final CTA -->
            <section id="contact" class="lp-cta-band">
                <div class="lp-container lp-cta-inner">
                    <h2 class="lp-cta-title">{{ L(content.cta.title) }}</h2>
                    <p class="lp-cta-sub">{{ L(content.cta.sub) }}</p>
                    <div class="lp-cta-actions">
                        <a href="#lead" class="btn lp-btn-lg lp-cta-btn" @click="onRequestDemo">{{ L(content.cta.button) }}</a>
                        <a v-if="waHref" :href="waHref" target="_blank" rel="noopener" class="btn btn-ghost lp-btn-lg lp-cta-wa" @click="onWhatsapp">{{ L(content.cta.whatsapp_label) }}</a>
                    </div>
                    <a v-if="content.contact.email" :href="`mailto:${content.contact.email}`" class="lp-cta-email">{{ content.contact.email }}</a>
                </div>
            </section>

            <!-- Footer -->
            <footer class="lp-footer">
                <div class="lp-container lp-footer-inner">
                    <div class="lp-brand">
                        <XorderLogo class="lp-logo-footer" />
                        <div class="lp-footer-tag">{{ L(content.footer.tagline) }}</div>
                    </div>
                    <div class="lp-footer-copy">© 2026 {{ t('app.title') }}. {{ L(content.footer.rights) }}</div>
                </div>
            </footer>
        </main>

        <!-- Floating WhatsApp -->
        <a v-if="content && floatingWa" :href="waHref" target="_blank" rel="noopener" class="lp-wa-float"
            :aria-label="L(content.hero.whatsapp_label)" @click="onWhatsapp">✆</a>

        <!-- Loading / error states -->
        <div v-if="!content" class="lp-boot">
            <p v-if="loadError" class="lp-boot-msg">Unable to load content. Please refresh.</p>
            <div v-else class="lp-boot-spin" aria-label="Loading"></div>
        </div>
    </div>
</template>

<style scoped>
.landing { background: var(--page); color: var(--body); min-height: 100vh; }
.lp-container { max-width: 1120px; margin: 0 auto; padding-inline: 24px; }

/* Header */
.lp-header { position: sticky; top: 0; z-index: 30; background: color-mix(in srgb, var(--page) 88%, transparent);
    backdrop-filter: blur(10px); border-bottom: 1px solid var(--line); }
.lp-nav { display: flex; align-items: center; justify-content: space-between; height: 68px; gap: 24px; }
.lp-brand { display: flex; align-items: center; gap: 11px; text-decoration: none; }
.lp-logo { height: 30px; width: auto; color: var(--ink); display: block; }
.lp-links { display: flex; gap: 28px; }
.lp-links a { color: var(--body); font-size: 16px; text-decoration: none; transition: color .15s; }
.lp-links a:hover { color: var(--accent); }
.lp-actions { display: flex; align-items: center; gap: 14px; }
.lp-lang { width: 38px; height: 38px; border-radius: 9px; display: grid; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--muted); transition: background .15s, color .15s; }
.lp-lang:hover { background: var(--accent-soft); color: var(--accent); }

/* Boot state */
.lp-boot { min-height: 70vh; display: grid; place-items: center; }
.lp-boot-msg { color: var(--muted); font-size: 16px; }
.lp-boot-spin { width: 38px; height: 38px; border-radius: 50%; border: 3px solid var(--line);
    border-top-color: var(--accent); animation: lp-spin .8s linear infinite; }
@keyframes lp-spin { to { transform: rotate(360deg); } }

/* Hero */
.lp-hero { padding: 64px 0 78px; overflow: hidden; }
.lp-hero-grid { display: grid; grid-template-columns: 1.05fr 0.95fr; gap: 56px; align-items: center; }
.lp-badge { display: inline-block; background: var(--accent-soft); color: var(--accent);
    font-size: 13px; font-weight: 600; padding: 6px 13px; border-radius: 20px; font-family: var(--font-display); }
.lp-h1 { font-family: var(--font-display); font-weight: 800; font-size: 50px; line-height: 1.1;
    color: var(--ink); margin: 18px 0 0; letter-spacing: -0.02em; }
.lp-lead { font-size: 19px; line-height: 1.62; color: var(--body); margin: 18px 0 0; max-width: 32em; }
.lp-trust { list-style: none; padding: 0; margin: 20px 0 0; display: flex; flex-wrap: wrap; gap: 10px 22px; }
.lp-trust li { display: flex; align-items: center; gap: 8px; font-weight: 600; color: var(--ink); font-size: 15px; }
.lp-trust-ic { display: grid; place-items: center; width: 22px; height: 22px; border-radius: 50%;
    background: var(--green-soft); color: var(--green); font-size: 13px; font-weight: 700; }
.lp-hero-cta { display: flex; gap: 14px; margin-top: 26px; flex-wrap: wrap; }
.lp-btn-lg { padding: 14px 28px; font-size: 17px; }
.lp-hero-wa { display: inline-flex; align-items: center; gap: 8px; margin-top: 16px; color: var(--green);
    font-weight: 600; font-size: 15.5px; text-decoration: none; }
.lp-hero-wa:hover { text-decoration: underline; }
.lp-wa-ic { display: grid; place-items: center; width: 26px; height: 26px; border-radius: 50%;
    background: var(--green); color: #fff; font-size: 14px; }
.lp-stats { display: flex; gap: 28px 40px; margin-top: 38px; flex-wrap: wrap; }
.lp-stats > div { display: flex; flex-direction: column; min-width: 100px; }
.lp-stat-num { font-family: var(--font-display); font-weight: 800; font-size: 28px; color: var(--ink); }
.lp-stat-lbl { font-size: 14.5px; color: var(--muted); margin-top: 2px; }

/* Phone mockup */
.lp-hero-art { position: relative; display: grid; place-items: center; }
.lp-phone { width: 288px; height: 580px; background: var(--sidebar); border-radius: 40px; padding: 12px;
    box-shadow: 0 40px 80px -30px rgba(42,30,20,.55); position: relative; }
.lp-phone-notch { position: absolute; top: 12px; left: 50%; transform: translateX(-50%); width: 120px; height: 24px;
    background: var(--sidebar); border-radius: 0 0 16px 16px; z-index: 2; }
.lp-phone-screen { background: var(--page); border-radius: 30px; height: 100%; padding: 22px 16px; overflow: hidden; }
.lp-menu-head { display: flex; align-items: center; gap: 11px; margin-top: 8px; }
.lp-menu-logo { width: 40px; height: 40px; border-radius: 11px; background: var(--accent); color: #fff;
    display: grid; place-items: center; font-family: var(--font-display); font-weight: 700; }
.lp-menu-name { font-family: var(--font-display); font-weight: 600; font-size: 16px; color: var(--ink); }
.lp-menu-tag { font-size: 12px; color: var(--muted); }
.lp-menu-cats { display: flex; gap: 7px; margin: 18px 0 14px; }
.lp-chip { font-size: 12px; font-weight: 600; padding: 5px 12px; border-radius: 16px; background: var(--card);
    border: 1px solid var(--line); color: var(--muted); font-family: var(--font-display); }
.lp-chip-on { background: var(--accent); color: #fff; border-color: var(--accent); }
.lp-menu-item { display: flex; align-items: center; gap: 11px; background: var(--card); border: 1px solid var(--line);
    border-radius: 13px; padding: 10px; margin-bottom: 10px; }
.lp-menu-thumb { width: 46px; height: 46px; border-radius: 9px; background: linear-gradient(135deg, var(--accent-soft), #efd9c5); flex-shrink: 0; }
.lp-menu-meta { flex: 1; min-width: 0; }
.lp-menu-itemname { font-family: var(--font-display); font-weight: 600; font-size: 14px; color: var(--ink); }
.lp-menu-desc { font-size: 11.5px; color: var(--muted); }
.lp-menu-price { font-family: var(--font-display); font-weight: 700; color: var(--accent); font-size: 15px; }
.lp-menu-order { margin-top: 6px; text-align: center; background: var(--accent); color: #fff; font-weight: 700;
    font-family: var(--font-display); font-size: 14px; padding: 11px; border-radius: 12px; }


/* Sections */
.lp-section { padding: 78px 0; scroll-margin-top: 76px; }
.lp-section-alt { background: var(--accent-soft); }
.lp-section-head { text-align: center; max-width: 42em; margin: 0 auto 44px; }
.lp-h2 { font-family: var(--font-display); font-weight: 800; font-size: 36px; color: var(--ink); letter-spacing: -0.01em; }
.lp-sub { font-size: 18px; color: var(--muted); margin-top: 12px; line-height: 1.6; }

/* Offer */
.lp-offer-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 14px; max-width: 820px; margin: 0 auto; }
.lp-offer-item { display: flex; align-items: center; gap: 13px; background: var(--card); border: 1px solid var(--line);
    border-radius: 14px; padding: 16px 18px; }
.lp-offer-ic { display: grid; place-items: center; width: 40px; height: 40px; border-radius: 11px; flex-shrink: 0;
    background: var(--accent-soft); color: var(--accent); font-size: 19px; }
.lp-offer-text { font-size: 16px; font-weight: 600; color: var(--ink); }

/* Problem / solution */
.lp-problem-grid { display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 28px; align-items: start; }
.lp-problem-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 12px; }
.lp-problem-list li { display: flex; align-items: flex-start; gap: 12px; background: var(--card); border: 1px solid var(--line);
    border-radius: 13px; padding: 15px 17px; font-size: 16px; color: var(--body); }
.lp-x { display: grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    background: var(--red-soft); color: var(--red); font-size: 12px; font-weight: 700; margin-top: 1px; }
.lp-solution { padding: 28px; border-color: var(--accent); }
.lp-solution-badge { display: inline-block; background: var(--accent); color: #fff; font-family: var(--font-display);
    font-weight: 600; font-size: 12.5px; padding: 4px 12px; border-radius: 16px; }
.lp-solution-title { font-family: var(--font-display); font-weight: 800; font-size: 23px; color: var(--ink); margin: 14px 0 8px; }
.lp-solution-text { font-size: 16.5px; line-height: 1.6; color: var(--body); }

/* No commission comparison */
.lp-compare { display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; max-width: 880px; margin: 0 auto; }
.lp-compare-col { border-radius: 18px; padding: 28px; }
.lp-compare-them { background: var(--card); border: 1px solid var(--line); }
.lp-compare-us { background: var(--ink); color: #fff; box-shadow: 0 24px 60px -30px var(--ink); }
.lp-compare-title { font-family: var(--font-display); font-weight: 700; font-size: 20px; margin-bottom: 16px; }
.lp-compare-them .lp-compare-title { color: var(--ink); }
.lp-compare-col ul { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 12px; }
.lp-compare-col li { display: flex; align-items: flex-start; gap: 11px; font-size: 16px; }
.lp-compare-them li { color: var(--body); }
.lp-check { display: grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; flex-shrink: 0;
    background: var(--green); color: #fff; font-size: 12px; font-weight: 700; }
.lp-compare-us .lp-x { background: rgba(255,255,255,.16); color: #fff; }

/* Features */
.lp-feature-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 22px; }
.lp-feature { padding: 28px; }
.lp-feature-ico { display: grid; place-items: center; width: 46px; height: 46px; border-radius: 12px;
    background: var(--accent-soft); color: var(--accent); font-size: 22px; }
.lp-feature-title { font-family: var(--font-display); font-weight: 700; font-size: 19px; color: var(--ink); margin: 18px 0 8px; }
.lp-feature-text { font-size: 16px; line-height: 1.62; color: var(--body); }

/* Demo */
.lp-demo-grid { display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 48px; align-items: center; }
.lp-demo-sub { margin: 12px 0 0; }
.lp-flow { list-style: none; padding: 0; margin: 26px 0 28px; display: flex; flex-direction: column; gap: 16px; }
.lp-flow li { display: flex; align-items: flex-start; gap: 14px; }
.lp-flow-num { display: grid; place-items: center; width: 36px; height: 36px; border-radius: 11px; flex-shrink: 0;
    background: var(--accent); color: #fff; font-family: var(--font-display); font-weight: 700; }
.lp-flow-title { display: block; font-family: var(--font-display); font-weight: 700; font-size: 17px; color: var(--ink); }
.lp-flow-text { display: block; font-size: 15px; color: var(--muted); margin-top: 2px; }
.lp-demo-card { display: flex; flex-direction: column; align-items: center; gap: 16px; padding: 34px; }
.lp-qr-img { width: 200px; height: 200px; display: block; border-radius: 8px; }
.lp-demo-stand { font-family: var(--font-display); font-weight: 600; color: var(--muted); font-size: 14px; }

/* Packages */
.lp-billing { display: flex; width: fit-content; gap: 4px; margin: 0 auto 28px; padding: 4px; border-radius: 999px;
    background: var(--card); border: 1px solid var(--line); }
.lp-billing-opt { display: inline-flex; align-items: center; gap: 8px; border: 0; cursor: pointer;
    background: transparent; color: var(--body); font-family: inherit; font-size: 15px; font-weight: 600;
    padding: 9px 20px; border-radius: 999px; transition: background .15s, color .15s; }
.lp-billing-opt.on { background: var(--accent); color: #fff; }
.lp-billing-save { font-size: 12px; font-weight: 700; padding: 2px 8px; border-radius: 999px;
    background: rgba(16,185,129,.15); color: #0f9d6b; }
.lp-billing-opt.on .lp-billing-save { background: rgba(255,255,255,.22); color: #fff; }
.lp-pricing-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); gap: 22px; max-width: 1000px; margin: 0 auto; }
.lp-plan { padding: 28px; display: flex; flex-direction: column; position: relative; }
.lp-plan-popular { border-color: var(--accent); box-shadow: 0 20px 50px -28px var(--accent); }
.lp-plan-badge { position: absolute; top: -12px; inset-inline-start: 28px; background: var(--accent); color: #fff;
    font-family: var(--font-display); font-weight: 600; font-size: 12.5px; padding: 4px 12px; border-radius: 16px; }
.lp-plan-name { font-family: var(--font-display); font-weight: 700; font-size: 21px; color: var(--ink); }
.lp-plan-note { font-size: 14.5px; color: var(--muted); margin: 8px 0 0; min-height: 3.2em; line-height: 1.5; }
.lp-plan-price { display: flex; align-items: baseline; gap: 4px; margin: 14px 0 4px; }
.lp-plan-amount { font-family: var(--font-display); font-weight: 800; font-size: 24px; color: var(--accent); }
.lp-plan-feats { list-style: none; padding: 0; margin: 18px 0 24px; display: flex; flex-direction: column; gap: 10px; flex: 1; }
.lp-plan-feats li { position: relative; padding-inline-start: 24px; font-size: 15px; color: var(--body); }
.lp-plan-feats li::before { content: '✓'; position: absolute; inset-inline-start: 0; color: var(--green); font-weight: 700; }
.lp-plan .btn { justify-content: center; }

/* Industries */
.lp-industries { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; max-width: 880px; margin: 0 auto; }
.lp-industry { display: inline-flex; align-items: center; gap: 9px; background: var(--card); border: 1px solid var(--line);
    border-radius: 30px; padding: 11px 20px; font-size: 16px; font-weight: 600; color: var(--ink); }
.lp-industry-ic { font-size: 19px; }

/* Lead form */
.lp-lead-grid { display: grid; grid-template-columns: 0.9fr 1.1fr; gap: 44px; align-items: start; }
.lp-lead-copy { padding-top: 8px; }
.lp-lead-card { padding: 28px; }
.lp-form { display: flex; flex-direction: column; gap: 14px; }
.lp-field { display: flex; flex-direction: column; gap: 6px; }
.lp-field > span { font-size: 13.5px; font-weight: 600; color: var(--ink); }
.lp-field input, .lp-field select, .lp-field textarea { width: 100%; padding: 11px 13px; border: 1px solid var(--line);
    border-radius: 11px; background: var(--page); font-family: inherit; font-size: 15px; color: var(--ink); }
.lp-field input:focus, .lp-field select:focus, .lp-field textarea:focus { outline: none; border-color: var(--accent); }
.lp-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.lp-form-submit { justify-content: center; margin-top: 4px; }
.lp-err { color: var(--red); font-size: 13px; }
.lp-lead-done { text-align: center; padding: 36px 16px; }
.lp-lead-done-ic { display: inline-grid; place-items: center; width: 56px; height: 56px; border-radius: 50%;
    background: var(--green-soft); color: var(--green); font-size: 28px; font-weight: 700; margin-bottom: 16px; }
.lp-lead-done p { font-size: 17px; color: var(--ink); font-weight: 600; }

/* CTA band */
.lp-cta-band { background: var(--sidebar); padding: 70px 0; scroll-margin-top: 76px; }
.lp-cta-inner { text-align: center; }
.lp-cta-title { font-family: var(--font-display); font-weight: 800; font-size: 34px; color: #fff; }
.lp-cta-sub { font-size: 18px; color: var(--sidebar-muted); margin: 12px 0 28px; }
.lp-cta-actions { display: flex; gap: 14px; justify-content: center; flex-wrap: wrap; }
.lp-cta-btn { background: var(--accent); color: #fff; }
.lp-cta-btn:hover { background: var(--accent-dark); }
.lp-cta-wa { background: transparent; color: #fff; border-color: rgba(255,255,255,.25); }
.lp-cta-wa:hover { border-color: rgba(255,255,255,.55); background: rgba(255,255,255,.06); }
.lp-cta-email { display: inline-block; margin-top: 20px; color: var(--sidebar-muted); font-size: 15px;
    text-decoration: none; border-bottom: 1px solid transparent; }
.lp-cta-email:hover { color: #fff; border-color: rgba(255,255,255,.4); }

/* Footer */
.lp-footer { background: var(--page); border-top: 1px solid var(--line); padding: 36px 0; }
.lp-footer-inner { display: flex; align-items: center; justify-content: space-between; gap: 20px; flex-wrap: wrap; }
.lp-footer-inner .lp-brand { flex-direction: column; align-items: flex-start; gap: 10px; }
.lp-logo-footer { height: 26px; width: auto; color: var(--ink); display: block; }
.lp-footer-tag { font-size: 13px; color: var(--muted); }
.lp-footer-copy { font-size: 13.5px; color: var(--muted); }

/* Floating WhatsApp */
.lp-wa-float { position: fixed; bottom: 22px; inset-inline-end: 22px; z-index: 40; width: 56px; height: 56px;
    border-radius: 50%; background: var(--green); color: #fff; display: grid; place-items: center; font-size: 26px;
    text-decoration: none; box-shadow: 0 14px 30px -8px rgba(31,122,61,.6); transition: transform .15s; }
.lp-wa-float:hover { transform: scale(1.06); }

/* Responsive */
@media (max-width: 900px) {
    .lp-hero-grid, .lp-problem-grid, .lp-demo-grid, .lp-lead-grid { grid-template-columns: 1fr; gap: 40px; }
    .lp-h1 { font-size: 40px; }
    .lp-links { display: none; }
    .lp-feature-grid { grid-template-columns: 1fr 1fr; }
    .lp-offer-grid { grid-template-columns: 1fr; }
    .lp-hero-art { order: -1; }
}
@media (max-width: 620px) {
    .lp-h1 { font-size: 33px; }
    .lp-h2 { font-size: 29px; }
    .lp-hero { padding: 40px 0 52px; }
    .lp-section { padding: 56px 0; }
    .lp-feature-grid, .lp-compare, .lp-field-row { grid-template-columns: 1fr; }
    .lp-stats { gap: 22px; }
    .lp-cta-title { font-size: 28px; }
}
</style>
