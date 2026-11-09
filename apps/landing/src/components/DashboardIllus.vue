<script setup>
defineProps({ label: { type: String, default: '' } })
</script>

<template>
                <svg class="lp-dash-illus" viewBox="0 0 980 620" xmlns="http://www.w3.org/2000/svg"
                    role="img" :aria-label="label">
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
</template>

<style scoped>
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
</style>
