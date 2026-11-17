<script setup>
// Floating WhatsApp button: bounces in after load, pulses two rings, gives the
// icon a short wiggle every few seconds and shows a tooltip now and then.
// All motion stops under prefers-reduced-motion (app.css).
defineProps({
    href: { type: String, required: true },
    label: { type: String, required: true },
})
defineEmits(['click'])
</script>

<template>
    <a class="waf" :href="href" target="_blank" rel="noopener" :aria-label="label" @click="$emit('click')">
        <svg class="waf-ic" width="30" height="30" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z" /></svg>
        <span class="waf-tip" aria-hidden="true">{{ label }}</span>
    </a>
</template>

<style scoped>
/* inset-inline-end: the left corner in Arabic, the right corner in English. */
.waf { position: fixed; bottom: 22px; inset-inline-end: 22px; z-index: 45; width: 60px; height: 60px; border-radius: 50%;
    background: #25d366; color: #fff; display: grid; place-items: center; text-decoration: none;
    box-shadow: 0 18px 36px -12px rgba(31,122,61,.65); transition: scale .2s ease;
    animation: waf-in .8s 1.2s cubic-bezier(.2,.7,.2,1) both; }
.waf:hover { scale: 1.08; } /* `scale`, not transform: the entrance animation owns transform */
.waf:focus-visible { outline: 2px solid var(--lp-amber); outline-offset: 3px; }
.waf::before, .waf::after { content: ''; position: absolute; inset: 0; border-radius: 50%; background: #25d366; z-index: -1;
    animation: waf-ring 2.4s 2s ease-out infinite; }
.waf::after { animation-delay: 3.2s; }
.waf-ic { display: block; animation: waf-wiggle 5s 2.5s ease-in-out infinite; }
.waf-tip { position: absolute; inset-inline-end: 72px; top: 50%; margin-top: -18px; white-space: nowrap; background: var(--card);
    color: var(--ink); font-weight: 700; font-size: 14px; padding: 8px 14px; border-radius: 12px; border: 1px solid var(--line);
    box-shadow: 0 12px 30px -14px rgba(42,30,20,.5); opacity: 0; pointer-events: none;
    animation: waf-tip 9s 3s ease-in-out infinite; }
.waf:hover .waf-tip, .waf:focus-visible .waf-tip { animation: none; opacity: 1; }

@keyframes waf-in { 0% { opacity: 0; transform: translateY(40px) scale(.6); } 60% { opacity: 1; transform: translateY(-6px) scale(1.06); } 100% { opacity: 1; transform: none; } }
@keyframes waf-ring { 0% { transform: scale(1); opacity: .55; } 100% { transform: scale(1.9); opacity: 0; } }
@keyframes waf-wiggle { 0%, 86%, 100% { transform: rotate(0); } 89% { transform: rotate(-14deg); } 92% { transform: rotate(12deg); } 95% { transform: rotate(-8deg); } 98% { transform: rotate(4deg); } }
@keyframes waf-tip { 0%, 8% { opacity: 0; } 14%, 40% { opacity: 1; } 46%, 100% { opacity: 0; } }

@media (max-width: 560px) { .waf-tip { display: none; } }
</style>
