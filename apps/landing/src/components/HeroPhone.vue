<script setup>
import { useI18n } from 'vue-i18n'

// Decorative phone showing what a diner sees. Generic food emoji and abstract
// bars (no real restaurant data), like the dashboard illustration.
defineProps({
    qrUrl: { type: String, default: '' },
    qrOk: { type: Boolean, default: true },
})
defineEmits(['qr-error'])

const { t } = useI18n()
const items = ['🍔', '🍕', '🥙', '🍰']
</script>

<template>
    <div class="hp" role="img" :aria-label="t('landing.phone_mock_note')">
        <div class="hp-phone" aria-hidden="true">
            <div class="hp-notch"></div>
            <div class="hp-screen">
                <div class="hp-top">
                    <span class="hp-logo"></span>
                    <span class="hp-bar hp-bar-strong"></span>
                </div>
                <div class="hp-hero-img"><span>🍽️</span></div>
                <div class="hp-search">{{ t('landing.phone_search') }}</div>
                <div class="hp-cats">
                    <span class="hp-cat on">{{ t('landing.phone_all') }}</span>
                    <span class="hp-cat"></span>
                    <span class="hp-cat"></span>
                </div>
                <div class="hp-grid">
                    <div v-for="em in items" :key="em" class="hp-card">
                        <span class="hp-em">{{ em }}</span>
                        <span class="hp-bar hp-bar-strong"></span>
                        <span class="hp-row"><span class="hp-bar"></span><span class="hp-add">{{ t('landing.phone_add') }}</span></span>
                    </div>
                </div>
            </div>
        </div>

        <span class="hp-chip hp-chip-1"><i aria-hidden="true">⚡</i>{{ t('landing.chip_instant') }}</span>
        <span class="hp-chip hp-chip-2"><i aria-hidden="true">🌐</i>{{ t('landing.chip_langs') }}</span>
        <span class="hp-chip hp-chip-3"><i aria-hidden="true">💬</i>{{ t('landing.chip_whatsapp') }}</span>
        <span class="hp-chip hp-chip-4"><i aria-hidden="true">🏪</i>{{ t('landing.chip_branches') }}</span>

        <div v-if="qrOk && qrUrl" class="hp-qr">
            <img :src="qrUrl" width="88" height="88" alt="" loading="lazy" @error="$emit('qr-error')" />
            <span>{{ t('landing.phone_scan') }}</span>
        </div>
    </div>
</template>

<style scoped>
.hp { position: relative; width: min(100%, 420px); height: 560px; margin-inline: auto; }
.hp-phone { position: absolute; top: 0; left: 50%; transform: translateX(-50%); width: 270px;
    height: 540px; border-radius: 40px; background: var(--ink); padding: 10px;
    box-shadow: 0 50px 90px -40px rgba(42,30,20,.55); }
.hp-notch { position: absolute; top: 14px; left: 50%; transform: translateX(-50%); width: 80px; height: 20px;
    background: var(--ink); border-radius: 12px; z-index: 2; }
.hp-screen { height: 100%; border-radius: 30px; background: var(--page); overflow: hidden; padding: 38px 14px 14px;
    display: flex; flex-direction: column; gap: 10px; }
.hp-top { display: flex; align-items: center; gap: 8px; }
.hp-logo { width: 26px; height: 26px; border-radius: 50%; background: var(--accent); }
.hp-bar { display: block; height: 7px; width: 52px; border-radius: 4px; background: var(--muted); opacity: .4; }
.hp-bar-strong { background: var(--ink); opacity: .75; width: 80px; }
.hp-hero-img { height: 96px; border-radius: 16px; display: grid; place-items: center; font-size: 42px;
    background: linear-gradient(135deg, var(--accent-soft), var(--accent)); }
.hp-search { border: 1px solid var(--line); background: var(--card); border-radius: 10px; padding: 7px 10px;
    font-size: 11px; color: var(--lp-muted); }
.hp-cats { display: flex; gap: 6px; }
.hp-cat { height: 24px; min-width: 40px; padding-inline: 10px; border-radius: 12px; background: var(--accent-soft);
    display: inline-grid; place-items: center; font-size: 11px; color: var(--lp-amber); }
.hp-cat.on { background: var(--lp-amber); color: #fff; font-weight: 700; }
.hp-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; flex: 1; min-height: 0; }
.hp-card { min-width: 0; background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 8px;
    display: flex; flex-direction: column; gap: 6px; }
.hp-em { font-size: 30px; text-align: center; line-height: 1.2; }
.hp-row { display: flex; align-items: center; justify-content: space-between; gap: 4px; margin-top: auto; }
.hp-row .hp-bar { width: 26px; }
.hp-add { font-size: 10px; font-weight: 700; background: var(--lp-amber); color: #fff; padding: 2px 8px; border-radius: 8px; }

.hp-chip { position: absolute; z-index: 3; display: inline-flex; align-items: center; gap: 6px; background: var(--card);
    border: 1px solid var(--line); border-radius: 999px; padding: 7px 13px; font-family: var(--font-display);
    font-weight: 700; font-size: 13px; color: var(--ink); box-shadow: 0 14px 30px -18px rgba(42,30,20,.55);
    animation: hp-float 6s ease-in-out infinite; }
.hp-chip i { font-style: normal; }
.hp-chip-1 { inset-block-start: 56px; inset-inline-start: -6px; }
.hp-chip-2 { inset-block-start: 170px; inset-inline-end: -10px; animation-delay: -1.5s; }
.hp-chip-3 { inset-block-start: 330px; inset-inline-start: -14px; animation-delay: -3s; }
.hp-chip-4 { inset-block-end: 70px; inset-inline-end: -6px; animation-delay: -4.5s; }
@keyframes hp-float { 50% { transform: translateY(-7px); } }

.hp-qr { position: absolute; z-index: 3; inset-block-end: 6px; inset-inline-start: -4px; background: var(--card);
    border: 1px solid var(--line); border-radius: 16px; padding: 8px; display: flex; flex-direction: column;
    align-items: center; gap: 4px; font-size: 11px; font-weight: 700; color: var(--ink);
    box-shadow: 0 18px 36px -20px rgba(42,30,20,.55); }
.hp-qr img { width: 88px; height: 88px; border-radius: 8px; display: block; }

@media (max-width: 560px) {
    .hp { height: 500px; }
    .hp-phone { width: 236px; height: 480px; }
    .hp-chip { font-size: 12px; padding: 6px 10px; }
    .hp-chip-1 { inset-inline-start: 0; }
    .hp-chip-2 { inset-inline-end: 0; }
    .hp-chip-3 { inset-inline-start: 0; }
    .hp-chip-4 { inset-inline-end: 0; }
}
@media (prefers-reduced-motion: reduce) { .hp-chip { animation: none; } }
</style>
