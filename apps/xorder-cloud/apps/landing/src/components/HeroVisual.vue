<script setup>
import { useI18n } from 'vue-i18n'
import heroPhoto from '../assets/hero-barista.jpg'

// Hero art: a real person behind a counter (Unsplash, Brooke Cagle — free
// Unsplash License), an incoming-order card, a scannable demo QR and a
// handwritten note. The order card is illustrative, not real data.
defineProps({
    qrUrl: { type: String, default: '' },
    qrOk: { type: Boolean, default: true },
})
defineEmits(['qr-error'])

const { t } = useI18n()
</script>

<template>
    <div class="hv">
        <div class="hv-photo">
            <img :src="heroPhoto" :alt="t('lp.hero.photo_alt')" width="840" height="1000" fetchpriority="high" />
        </div>

        <div class="hv-order" aria-hidden="true">
            <div class="hv-order-head"><span class="hv-pulse"></span>{{ t('lp.hero.order_new') }}</div>
            <div class="hv-order-body">
                <span>{{ t('lp.hero.order_items') }}</span>
                <span class="hv-muted">{{ t('lp.hero.order_pickup') }}</span>
                <span class="hv-total">{{ t('lp.hero.order_total') }} · <i></i></span>
            </div>
        </div>

        <div v-if="qrOk && qrUrl" class="hv-qr">
            <img :src="qrUrl" width="64" height="64" alt="" loading="lazy" @error="$emit('qr-error')" />
            <span class="hv-qr-text">
                <strong>{{ t('lp.hero.scan_title') }}</strong>
                <span>{{ t('lp.hero.scan_sub') }}</span>
            </span>
        </div>

        <span class="hv-note lp-hand">{{ t('lp.hero.note') }}</span>
        <svg class="hv-arrow" viewBox="0 0 80 60" aria-hidden="true">
            <path d="M70 6c-6 26-26 40-58 44m0 0l12-10m-12 10l14 6" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
    </div>
</template>

<style scoped>
.hv { position: relative; width: 100%; max-width: 460px; height: 560px; margin-inline: auto; }
.hv-photo { position: absolute; inset-inline-start: 0; top: 0; width: 86%; height: 470px; overflow: hidden;
    border-radius: 36px 36px 36px 120px; background: var(--accent-soft); border: 1px solid #f6d7a3;
    animation: hv-in .9s .2s cubic-bezier(.2,.7,.2,1) both; }
.hv-photo img { display: block; width: 100%; height: 100%; object-fit: cover; }

.hv-order { position: absolute; inset-inline-end: 0; top: 150px; width: 270px; background: var(--card); border-radius: 22px;
    border: 1px solid var(--line); box-shadow: 0 30px 60px -30px rgba(42,30,20,.45); overflow: hidden;
    animation: hv-float 6s ease-in-out infinite; }
.hv-order-head { background: var(--green); color: #fff; padding: 11px 16px; font-weight: 700; font-size: 14px;
    display: flex; align-items: center; gap: 8px; }
.hv-pulse { width: 9px; height: 9px; border-radius: 50%; background: #fff; animation: hv-pulse 1.8s ease-out infinite; }
.hv-order-body { padding: 14px 16px; display: flex; flex-direction: column; gap: 6px; font-size: 14.5px; color: var(--ink); }
.hv-muted { color: var(--lp-muted); }
.hv-total { font-weight: 800; display: flex; align-items: center; gap: 6px; }
.hv-total i { display: inline-block; width: 44px; height: 9px; border-radius: 5px; background: var(--accent); }

.hv-qr { position: absolute; inset-inline-start: 22px; bottom: 6px; display: flex; align-items: center; gap: 12px;
    background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 10px 10px 10px 14px;
    box-shadow: 0 18px 36px -20px rgba(42,30,20,.5); animation: hv-bob 5s ease-in-out -2s infinite; }
.hv-qr img { width: 64px; height: 64px; border-radius: 10px; display: block; }
.hv-qr-text { display: flex; flex-direction: column; font-size: 13px; color: var(--lp-muted); }
.hv-qr-text strong { font-size: 15px; color: var(--ink); font-weight: 800; }

.hv-note { position: absolute; inset-inline-end: 10px; top: 54px; font-size: 24px; color: var(--lp-amber);
    background: color-mix(in srgb, var(--page) 92%, transparent); padding: 2px 12px 6px; border-radius: 12px; /* readable over the photo */
    animation: hv-sway 4s ease-in-out infinite; }
.hv-arrow { position: absolute; inset-inline-end: 70px; top: 88px; width: 70px; height: 54px; color: var(--lp-amber); }
[dir='ltr'] .hv-arrow { transform: scaleX(-1); }

@keyframes hv-in { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: none; } }
@keyframes hv-float { 0%, 100% { transform: rotate(2deg) translateY(0); } 50% { transform: rotate(2deg) translateY(-10px); } }
@keyframes hv-bob { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }
@keyframes hv-sway { 0%, 100% { transform: rotate(-6deg); } 50% { transform: rotate(-3deg) translateY(-3px); } }
@keyframes hv-pulse { 0% { box-shadow: 0 0 0 0 rgba(255,255,255,.7); } 70%, 100% { box-shadow: 0 0 0 8px rgba(255,255,255,0); } }

@media (max-width: 560px) {
    .hv { height: 500px; }
    .hv-photo { height: 410px; }
    .hv-order { width: 230px; top: 130px; }
    .hv-note { font-size: 20px; }
}
</style>
