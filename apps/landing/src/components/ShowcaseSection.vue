<script setup>
import { useI18n } from 'vue-i18n'
import DashboardIllus from './DashboardIllus.vue'

// Dashboard + WhatsApp-order showcases. Copy comes from content.showcase
// (bilingual, admin-managed); the visuals are illustrative, not real data.
const props = defineProps({ showcase: { type: Object, default: () => ({}) } })
const { t, locale } = useI18n()
const L = (f) => (f && (f[locale.value] ?? f.en)) || ''
const has = (k) => !!(props.showcase?.[k] && (L(props.showcase[k].title) || L(props.showcase[k].text)))
</script>

<template>
    <section v-if="has('dashboard') || has('whatsapp')" id="showcase" class="sc">
        <div class="lp-container">
            <div v-if="has('dashboard')" class="sc-row">
                <div class="sc-copy">
                    <span class="lp-eyebrow">{{ t('landing.showcase_eyebrow') }}</span>
                    <h2 class="lp-h2">{{ L(showcase.dashboard.title) }}</h2>
                    <p class="lp-sub">{{ L(showcase.dashboard.text) }}</p>
                    <div class="sc-pills" aria-hidden="true">
                        <span>{{ t('landing.chip_instant') }}</span>
                        <span>{{ t('landing.chip_langs') }}</span>
                        <span>{{ t('landing.chip_branches') }}</span>
                    </div>
                </div>
                <div class="sc-visual sc-dash">
                    <DashboardIllus :label="t('landing.showcase_eyebrow')" />
                    <span class="sc-note">{{ t('landing.phone_mock_note') }}</span>
                </div>
            </div>

            <div v-if="has('whatsapp')" class="sc-row sc-row-flip">
                <div class="sc-copy">
                    <span class="lp-eyebrow">{{ t('landing.wa_eyebrow') }}</span>
                    <h2 class="lp-h2">{{ L(showcase.whatsapp.title) }}</h2>
                    <p class="lp-sub">{{ L(showcase.whatsapp.text) }}</p>
                </div>
                <div class="sc-visual">
                    <div class="wa" role="img" :aria-label="t('landing.wa_new_order')">
                        <div class="wa-head"><span class="wa-dot"></span>{{ t('landing.wa_new_order') }}</div>
                        <div class="wa-bubble">
                            <strong>{{ t('landing.wa_new_order') }}</strong>
                            <span>{{ t('landing.wa_items') }}</span>
                            <span>{{ t('landing.wa_pickup') }}</span>
                            <span class="wa-total">{{ t('landing.wa_total') }} · <i></i></span>
                        </div>
                    </div>
                    <span class="sc-note">{{ t('landing.phone_mock_note') }}</span>
                </div>
            </div>
        </div>
    </section>
</template>

<style scoped>
/* LandingView's scoped helpers don't reach child components; mirror them here. */
.lp-container { width: min(calc(100% - 48px), 1200px); margin-inline: auto; }
.lp-eyebrow { display: inline-block; font-family: var(--font-display); font-weight: 700; font-size: 13px;
    letter-spacing: .06em; text-transform: uppercase; color: var(--lp-amber); margin-bottom: 12px; }
.lp-h2 { font-family: var(--font-display); font-weight: 800; font-size: clamp(26px, 4vw, 38px); color: var(--ink);
    letter-spacing: -0.01em; line-height: 1.15; }
.lp-sub { font-size: clamp(15px, 2vw, 18px); color: var(--lp-muted); margin-top: 12px; line-height: 1.6; }
@media (max-width: 560px) { .lp-container { width: calc(100% - 32px); } }

.sc { padding: clamp(40px, 5vw, 64px) 0; scroll-margin-top: 80px; }
.sc-row { display: grid; grid-template-columns: 1fr 1.1fr; gap: clamp(28px, 5vw, 64px); align-items: center; }
.sc-row + .sc-row { margin-top: clamp(36px, 5vw, 64px); }
.sc-row-flip { grid-template-columns: 1.1fr 1fr; }
.sc-row-flip .sc-copy { order: 2; }
.sc-copy .lp-sub { max-width: 30em; }
.sc-pills { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 18px; }
.sc-pills span { background: var(--accent-soft); color: var(--lp-amber); font-weight: 700; font-size: 13px;
    padding: 6px 13px; border-radius: 999px; }
.sc-visual { display: flex; flex-direction: column; align-items: center; gap: 8px; }
.sc-dash :deep(svg) { width: 100%; max-width: 560px; height: auto; display: block; }
.sc-note { font-size: 12px; color: var(--lp-muted); }

.wa { width: min(100%, 360px); border-radius: 22px; overflow: hidden; background: #e9e2d6; border: 1px solid var(--line);
    box-shadow: 0 40px 70px -44px rgba(42,30,20,.55); }
.wa-head { background: #1f7a3d; color: #fff; padding: 12px 16px; font-weight: 700; display: flex; align-items: center; gap: 8px; }
.wa-dot { width: 10px; height: 10px; border-radius: 50%; background: #fff; }
.wa-bubble { margin: 18px 16px; background: #fff; color: var(--ink); border-radius: 14px; padding: 14px 16px;
    display: flex; flex-direction: column; gap: 6px; font-size: 14.5px; }
.wa-total { font-weight: 800; display: flex; align-items: center; gap: 6px; }
.wa-total i { display: inline-block; width: 44px; height: 9px; border-radius: 5px; background: var(--accent); }

@media (max-width: 980px) {
    .sc-row, .sc-row-flip { grid-template-columns: 1fr; }
    .sc-row-flip .sc-copy { order: 0; }
}
</style>
