<script setup>
import { useI18n } from 'vue-i18n'
import { vReveal } from '../lib/reveal.js'

// "Guests build the order, then send it ready": a cart becomes one WhatsApp
// message, instead of the back-and-forth questions struck through below it.
// Illustrative only — no real menu data.
const { t, tm, rt } = useI18n()
</script>

<template>
    <div class="ws">
        <div class="ws-copy" v-reveal>
            <span class="lp-eyebrow">{{ t('lp.wa.eyebrow') }}</span>
            <h2 class="lp-h2">{{ t('lp.wa.title') }}</h2>
            <p class="lp-sub">{{ t('lp.wa.text') }}</p>
        </div>

        <div class="ws-visual" v-reveal="0.1">
            <div class="ws-flow" role="img" :aria-label="t('lp.wa.visual_label')">
                <div class="ws-cart ws-a1" aria-hidden="true">
                    <div class="ws-cart-head"><strong>{{ t('lp.wa.cart') }}</strong><span>{{ t('lp.wa.cart_count') }}</span></div>
                    <div v-for="(it, i) in tm('lp.wa.items')" :key="i" class="ws-row">
                        <span>{{ rt(it.name) }}</span><span class="ws-qty">× {{ rt(it.qty) }}</span>
                    </div>
                    <div class="ws-sum"><span>{{ t('lp.wa.total') }}</span><i></i></div>
                    <span class="ws-send">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 11.6a8.5 8.5 0 01-12.6 7.4L3.5 20.5l1.5-4.3A8.5 8.5 0 1120.5 11.6z" /></svg>
                        {{ t('lp.wa.send') }}
                    </span>
                </div>

                <svg class="ws-arrow ws-a2" width="44" height="28" viewBox="0 0 44 28" aria-hidden="true">
                    <path d="M40 14H6m0 0l9-9m-9 9l9 9" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
                </svg>

                <div class="ws-chat ws-a3" aria-hidden="true">
                    <div class="ws-chat-head">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 11.6a8.5 8.5 0 01-12.6 7.4L3.5 20.5l1.5-4.3A8.5 8.5 0 1120.5 11.6z" /></svg>
                        {{ t('lp.wa.shop') }}
                    </div>
                    <div class="ws-bubble">
                        <strong>{{ t('lp.wa.msg_title') }}</strong>
                        <span v-for="(l, i) in tm('lp.wa.msg_lines')" :key="i">{{ rt(l) }}</span>
                        <span class="ws-bubble-total">{{ t('lp.wa.total') }} · <i></i></span>
                    </div>
                </div>
            </div>

            <div class="ws-before">
                <span class="lp-hand ws-instead">{{ t('lp.wa.instead') }}</span>
                <s v-for="(b, i) in tm('lp.wa.before')" :key="i">{{ rt(b) }}</s>
            </div>
            <span class="ws-note">{{ t('lp.dash.example') }}</span>
        </div>
    </div>
</template>

<style scoped>
.ws { display: grid; grid-template-columns: 1fr 1.15fr; gap: clamp(28px, 5vw, 56px); align-items: center; }
.ws-copy .lp-sub { max-width: 30em; }
.ws-visual { display: flex; flex-direction: column; align-items: center; gap: 14px; order: -1; }
.ws-flow { width: 100%; max-width: 560px; display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 14px; }

.ws-cart { flex: 1 1 220px; max-width: 250px; background: var(--card); border: 1px solid var(--line); border-radius: 24px;
    padding: 18px; box-shadow: 0 30px 60px -36px rgba(42,30,20,.5); font-size: 14.5px; }
.ws-cart-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
.ws-cart-head strong { font-size: 16px; color: var(--ink); }
.ws-cart-head span { font-size: 12.5px; color: var(--lp-muted); }
.ws-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 9px 0;
    border-bottom: 1px dashed var(--line); font-weight: 700; color: var(--ink); }
.ws-qty { flex: none; font-size: 13px; color: var(--lp-amber); background: var(--accent-soft); border-radius: 8px; padding: 2px 8px; }
.ws-sum { display: flex; align-items: center; justify-content: space-between; margin: 12px 0 14px; font-weight: 800; color: var(--ink); }
.ws-sum i, .ws-bubble-total i { display: inline-block; width: 44px; height: 9px; border-radius: 5px; background: var(--accent); }
.ws-send { display: flex; align-items: center; justify-content: center; gap: 8px; background: var(--green); color: #fff;
    border-radius: 999px; padding: 11px 12px; font-weight: 700; font-size: 14px; }

.ws-arrow { flex: none; color: var(--lp-amber); }
[dir='ltr'] .ws-arrow { transform: scaleX(-1); }

.ws-chat { flex: 1 1 220px; max-width: 250px; border-radius: 24px; overflow: hidden; background: #efe7da;
    border: 1px solid var(--line); box-shadow: 0 30px 60px -36px rgba(42,30,20,.5); }
.ws-chat-head { background: var(--green); color: #fff; padding: 11px 14px; font-weight: 700; font-size: 14px;
    display: flex; align-items: center; gap: 8px; }
.ws-bubble { margin: 14px 12px; margin-inline-start: auto; max-width: 92%; background: #d9f2df; border-radius: 16px 16px 4px 16px;
    padding: 10px 12px; font-size: 13.5px; line-height: 1.7; color: var(--ink); display: flex; flex-direction: column; }
.ws-bubble-total { font-weight: 800; display: flex; align-items: center; gap: 6px; }

.ws-before { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; justify-content: center; }
.ws-instead { font-size: 20px; color: var(--lp-amber); }
.ws-before s { font-size: 13.5px; color: var(--lp-muted); background: var(--card); border: 1px solid var(--line);
    border-radius: 14px; padding: 6px 12px; }
.ws-note { font-size: 12.5px; color: var(--lp-muted); }

/* Loop: cart appears, arrow, then the sent message; fade out, repeat. */
.ws-a1 { animation: ws-a1 9s ease-in-out infinite; }
.ws-a2 { animation: ws-a2 9s ease-in-out infinite; }
.ws-a3 { animation: ws-a3 9s ease-in-out infinite; }
@keyframes ws-a1 { 0% { opacity: 0; transform: translateY(10px); } 6%, 88% { opacity: 1; transform: none; } 96%, 100% { opacity: 0; } }
@keyframes ws-a2 { 0%, 18% { opacity: 0; transform: translateY(10px); } 24%, 88% { opacity: 1; transform: none; } 96%, 100% { opacity: 0; } }
@keyframes ws-a3 { 0%, 36% { opacity: 0; transform: translateY(10px); } 42%, 88% { opacity: 1; transform: none; } 96%, 100% { opacity: 0; } }
[dir='ltr'] .ws-a2 { animation-name: ws-a2-ltr; }
@keyframes ws-a2-ltr { 0%, 18% { opacity: 0; transform: scaleX(-1) translateY(10px); } 24%, 88% { opacity: 1; transform: scaleX(-1); } 96%, 100% { opacity: 0; transform: scaleX(-1); } }

@media (max-width: 980px) {
    .ws { grid-template-columns: 1fr; }
    .ws-visual { order: 0; }
}
</style>
