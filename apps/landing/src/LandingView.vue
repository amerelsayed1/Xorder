<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { setLocale } from '@xorder/ui/i18n'
import XorderLogo from '@xorder/ui/XorderLogo.vue'
import Icon from '@xorder/ui/Icon.vue'
import { fetchLandingContent } from './lib/content.js'

const { t, locale } = useI18n()

// Admin-managed content (bilingual). Sections render once it has loaded.
const content = ref(null)
const loadError = ref(false)

onMounted(async () => {
    try {
        content.value = await fetchLandingContent()
    } catch {
        loadError.value = true
    }
})

// Pick the active locale from a bilingual { en, ar } field.
const L = (field) => (field && (field[locale.value] ?? field.en)) || ''

// "Log in" points to the super-admin portal on the admin subdomain.
const adminLoginUrl = `${window.location.protocol}//admin.${window.location.host}/login`

function toggleLang() { setLocale(locale.value === 'ar' ? 'en' : 'ar') }
const targetLocaleKey = () => locale.value === 'ar' ? 'languages.en' : 'languages.ar'
const targetLocaleAriaKey = () => locale.value === 'ar' ? 'common.switch_to_english' : 'common.switch_to_arabic'
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
                    <a href="#features">{{ t('landing.nav_features') }}</a>
                    <a href="#how">{{ t('landing.nav_how') }}</a>
                </nav>

                <div class="lp-actions">
                    <a :href="adminLoginUrl" class="lp-login">{{ t('landing.login') }}</a>
                    <a href="#contact" class="btn btn-accent">{{ t('landing.get_started') }}</a>
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
                        <div class="lp-hero-cta">
                            <a href="#contact" class="btn btn-accent lp-btn-lg">{{ L(content.hero.cta) }}</a>
                            <a href="/r/demo" class="btn btn-ghost lp-btn-lg">{{ L(content.hero.secondary) }}</a>
                        </div>

                        <div class="lp-stats">
                            <div v-for="(p, i) in content.proof" :key="i">
                                <span class="lp-stat-num">{{ L(p.title) }}</span>
                                <span class="lp-stat-lbl">{{ L(p.text) }}</span>
                            </div>
                        </div>
                    </div>

                    <!-- Phone mockup (static demo) -->
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
                            </div>
                        </div>
                        <div class="lp-qr-float">
                            <div class="lp-qr-grid">
                                <span v-for="n in 64" :key="n" :class="['lp-qr-cell', (n * 7 + (n % 5)) % 3 === 0 ? 'on' : '']"></span>
                            </div>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Features -->
            <section id="features" class="lp-section">
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

            <!-- How it works -->
            <section id="how" class="lp-section lp-section-alt">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.steps.title) }}</h2>
                    </div>
                    <div class="lp-steps">
                        <div class="lp-step" v-for="(s, i) in content.steps.items" :key="i">
                            <div class="lp-step-num">{{ i + 1 }}</div>
                            <h3 class="lp-feature-title">{{ L(s.title) }}</h3>
                            <p class="lp-feature-text">{{ L(s.text) }}</p>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Pricing -->
            <section id="pricing" class="lp-section">
                <div class="lp-container">
                    <div class="lp-section-head">
                        <h2 class="lp-h2">{{ L(content.pricing.title) }}</h2>
                        <p class="lp-sub">{{ L(content.pricing.sub) }}</p>
                    </div>
                    <div class="lp-pricing-grid">
                        <div class="lp-plan card" v-for="(plan, i) in content.pricing.plans" :key="i" :class="{ 'lp-plan-popular': plan.popular }">
                            <span v-if="plan.popular" class="lp-plan-badge">{{ L(content.pricing.popular_label) }}</span>
                            <h3 class="lp-plan-name">{{ L(plan.name) }}</h3>
                            <div class="lp-plan-price">
                                <span class="lp-plan-amount">{{ L(plan.price) }}</span>
                                <span class="lp-plan-per">{{ L(plan.per) }}</span>
                            </div>
                            <p class="lp-plan-note">{{ L(plan.note) }}</p>
                            <ul class="lp-plan-feats">
                                <li v-for="(feat, fi) in plan.features" :key="fi">{{ L(feat) }}</li>
                            </ul>
                            <a href="#contact" class="btn lp-btn-lg" :class="plan.popular ? 'btn-accent' : 'btn-ghost'">
                                {{ L(content.pricing.choose_label) }}
                            </a>
                        </div>
                    </div>
                </div>
            </section>

            <!-- Contact -->
            <section id="contact" class="lp-cta-band">
                <div class="lp-container lp-cta-inner">
                    <h2 class="lp-cta-title">{{ L(content.cta.title) }}</h2>
                    <p class="lp-cta-sub">{{ L(content.cta.sub) }}</p>
                    <div class="lp-cta-actions">
                        <a :href="`mailto:${content.contact.email}`" class="btn lp-btn-lg lp-cta-btn">{{ L(content.cta.button) }}</a>
                        <a v-if="content.contact.whatsapp" :href="`https://wa.me/${content.contact.whatsapp}`" target="_blank" rel="noopener" class="btn btn-ghost lp-btn-lg lp-cta-wa">{{ L(content.cta.whatsapp_label) }}</a>
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

        <!-- Loading / error states -->
        <div v-else class="lp-boot">
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
.lp-brand-name { font-family: var(--font-display); font-weight: 600; font-size: 18px; color: var(--ink); }
.lp-logo { height: 30px; width: auto; color: var(--ink); display: block; }
.lp-links { display: flex; gap: 28px; }
.lp-links a { color: var(--body); font-size: 16px; text-decoration: none; transition: color .15s; }
.lp-links a:hover { color: var(--accent); }
.lp-actions { display: flex; align-items: center; gap: 14px; }
.lp-lang { width: 38px; height: 38px; border-radius: 9px; display: grid; place-items: center;
    background: none; border: none; cursor: pointer; color: var(--muted); transition: background .15s, color .15s; }
.lp-lang:hover { background: var(--accent-soft); color: var(--accent); }
.lp-login { color: var(--ink); font-size: 16px; font-weight: 500; text-decoration: none; }
.lp-login:hover { color: var(--accent); }

/* Boot state */
.lp-boot { min-height: 70vh; display: grid; place-items: center; }
.lp-boot-msg { color: var(--muted); font-size: 16px; }
.lp-boot-spin { width: 38px; height: 38px; border-radius: 50%; border: 3px solid var(--line);
    border-top-color: var(--accent); animation: lp-spin .8s linear infinite; }
@keyframes lp-spin { to { transform: rotate(360deg); } }

/* Hero */
.lp-hero { padding: 72px 0 84px; overflow: hidden; }
.lp-hero-grid { display: grid; grid-template-columns: 1.05fr 0.95fr; gap: 56px; align-items: center; }
.lp-badge { display: inline-block; background: var(--accent-soft); color: var(--accent);
    font-size: 13px; font-weight: 600; padding: 6px 13px; border-radius: 20px; font-family: var(--font-display); }
.lp-h1 { font-family: var(--font-display); font-weight: 800; font-size: 56px; line-height: 1.08;
    color: var(--ink); margin: 18px 0 0; letter-spacing: -0.02em; }
.lp-lead { font-size: 19.5px; line-height: 1.62; color: var(--body); margin: 20px 0 0; max-width: 30em; }
.lp-hero-cta { display: flex; gap: 14px; margin-top: 30px; flex-wrap: wrap; }
.lp-btn-lg { padding: 14px 28px; font-size: 17px; }
.lp-stats { display: flex; gap: 28px 40px; margin-top: 44px; flex-wrap: wrap; }
.lp-stats > div { display: flex; flex-direction: column; min-width: 118px; }
.lp-stat-num { font-family: var(--font-display); font-weight: 800; font-size: 28px; color: var(--ink); }
.lp-stat-lbl { font-size: 14.5px; color: var(--muted); margin-top: 2px; }

/* Phone mockup */
.lp-hero-art { position: relative; display: grid; place-items: center; }
.lp-phone { width: 290px; height: 580px; background: var(--sidebar); border-radius: 40px; padding: 12px;
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

.lp-qr-float { position: absolute; bottom: 24px; inset-inline-end: -8px; background: #fff; border-radius: 18px;
    padding: 14px; box-shadow: 0 20px 50px -18px rgba(42,30,20,.5); border: 1px solid var(--line); }
.lp-qr-grid { width: 92px; height: 92px; display: grid; grid-template-columns: repeat(8, 1fr); gap: 2px; }
.lp-qr-cell { background: transparent; border-radius: 2px; }
.lp-qr-cell.on { background: var(--ink); }

/* Sections */
.lp-section { padding: 84px 0; scroll-margin-top: 80px; }
.lp-section-alt { background: var(--accent-soft); }
.lp-section-head { text-align: center; max-width: 40em; margin: 0 auto 48px; }
.lp-h2 { font-family: var(--font-display); font-weight: 800; font-size: 38px; color: var(--ink); letter-spacing: -0.01em; }
.lp-sub { font-size: 18px; color: var(--muted); margin-top: 12px; }

/* Features */
.lp-feature-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 22px; }
.lp-feature { padding: 28px; }
.lp-feature-ico { display: grid; place-items: center; width: 46px; height: 46px; border-radius: 12px;
    background: var(--accent-soft); color: var(--accent); font-size: 22px; }
.lp-feature-title { font-family: var(--font-display); font-weight: 700; font-size: 19px; color: var(--ink); margin: 18px 0 8px; }
.lp-feature-text { font-size: 16px; line-height: 1.62; color: var(--body); }

/* Steps */
.lp-steps { display: grid; grid-template-columns: repeat(3, 1fr); gap: 28px; }
.lp-step { text-align: center; padding: 8px; }
.lp-step-num { width: 54px; height: 54px; margin: 0 auto 18px; border-radius: 16px; background: var(--accent); color: #fff;
    display: grid; place-items: center; font-family: var(--font-display); font-weight: 700; font-size: 24px; }

/* Pricing */
.lp-pricing-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 22px; max-width: 760px; margin: 0 auto; }
.lp-plan { padding: 28px; display: flex; flex-direction: column; position: relative; }
.lp-plan-popular { border-color: var(--accent); box-shadow: 0 20px 50px -28px var(--accent); }
.lp-plan-badge { position: absolute; top: -12px; inset-inline-start: 28px; background: var(--accent); color: #fff;
    font-family: var(--font-display); font-weight: 600; font-size: 12.5px; padding: 4px 12px; border-radius: 16px; }
.lp-plan-name { font-family: var(--font-display); font-weight: 700; font-size: 20px; color: var(--ink); }
.lp-plan-price { display: flex; align-items: baseline; gap: 4px; margin: 14px 0 4px; }
.lp-plan-amount { font-family: var(--font-display); font-weight: 800; font-size: 38px; color: var(--ink); }
.lp-plan-per { font-size: 15px; color: var(--muted); }
.lp-plan-note { font-size: 14.5px; color: var(--muted); min-height: 2.6em; }
.lp-plan-feats { list-style: none; padding: 0; margin: 18px 0 24px; display: flex; flex-direction: column; gap: 10px; flex: 1; }
.lp-plan-feats li { position: relative; padding-inline-start: 24px; font-size: 15px; color: var(--body); }
.lp-plan-feats li::before { content: '✓'; position: absolute; inset-inline-start: 0; color: var(--green); font-weight: 700; }
.lp-plan .btn { justify-content: center; }

/* CTA band */
.lp-cta-band { background: var(--sidebar); padding: 72px 0; scroll-margin-top: 80px; }
.lp-cta-inner { text-align: center; }
.lp-cta-title { font-family: var(--font-display); font-weight: 800; font-size: 36px; color: #fff; }
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

/* Responsive */
@media (max-width: 900px) {
    .lp-hero-grid { grid-template-columns: 1fr; gap: 48px; }
    .lp-h1 { font-size: 44px; }
    .lp-links { display: none; }
    .lp-feature-grid, .lp-steps { grid-template-columns: 1fr; }
    .lp-login { display: none; }
}
@media (max-width: 560px) {
    .lp-h1 { font-size: 36px; }
    .lp-stats { gap: 24px; }
    .lp-hero { padding: 44px 0 56px; }
}
</style>
