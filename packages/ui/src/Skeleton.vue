<script setup>
// A single shimmering placeholder block. Size it with w / h / rounded.
defineProps({
    w: { type: String, default: '100%' },
    h: { type: String, default: '16px' },
    rounded: { type: String, default: '8px' },
})
</script>

<template>
    <div class="xo-skel" :style="{ width: w, height: h, borderRadius: rounded }" />
</template>

<style scoped>
.xo-skel { position: relative; overflow: hidden; background: var(--line, #e6e6e6); }
.xo-skel::after {
    content: '';
    position: absolute;
    inset: 0;
    transform: translateX(-100%);
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, .6), transparent);
    animation: xo-shimmer 1.3s infinite;
}
@media (prefers-reduced-motion: reduce) {
    .xo-skel::after { animation: none; }
}
@keyframes xo-shimmer { 100% { transform: translateX(100%); } }
</style>
