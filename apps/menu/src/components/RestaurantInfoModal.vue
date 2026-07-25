<script setup>
import { computed } from 'vue'
import { useRestaurantIdentity } from '../composables/useRestaurantIdentity'
import { safeUrl } from '../lib/safeUrl'

const props = defineProps({
    restaurant: Object,
    isAr: Boolean,
    t: Function,
    localize: Function,
})

const emit = defineEmits(['close'])

const { primaryName: name, initial } = useRestaurantIdentity(props)
const r = computed(() => props.restaurant || {})

// getDay() index → business_hours key. Display starts on Saturday to match the
// Arabic week; each row still resolves its own weekday via DAY_KEYS.
const DAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
const DISPLAY_ORDER = ['sat', 'sun', 'mon', 'tue', 'wed', 'thu', 'fri']
const WEEKDAY_INDEX = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }

const hours = computed(() => r.value.business_hours || {})
const hasStructuredHours = computed(() =>
    DAY_KEYS.some((k) => {
        const d = hours.value[k]
        return d && (d.closed || (d.open && d.close))
    }),
)

function toMin(hhmm) {
    if (!hhmm) return null
    const [h, m] = String(hhmm).split(':').map(Number)
    if (Number.isNaN(h) || Number.isNaN(m)) return null
    return h * 60 + m
}

// "Now" resolved in the restaurant's own timezone, so the open/closed badge is
// correct no matter where the diner is browsing from.
function nowInRestaurantTz() {
    const tz = r.value.timezone || undefined
    try {
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: tz, weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
        }).formatToParts(new Date())
        const get = (type) => parts.find((p) => p.type === type)?.value
        let hour = Number(get('hour'))
        if (hour === 24) hour = 0
        return { dayIdx: WEEKDAY_INDEX[get('weekday')] ?? 0, min: hour * 60 + Number(get('minute')) }
    } catch {
        return null
    }
}

function formatTime(hhmm) {
    const min = toMin(hhmm)
    if (min === null) return ''
    const d = new Date(2000, 0, 1, Math.floor(min / 60), min % 60)
    return new Intl.DateTimeFormat(props.isAr ? 'ar-EG' : 'en-US', {
        hour: 'numeric', minute: '2-digit', hour12: true,
    }).format(d)
}

// Whether the restaurant is open right now, and if so the time it next closes.
const status = computed(() => {
    if (!hasStructuredHours.value) return null
    const now = nowInRestaurantTz()
    if (!now) return null

    const windowFor = (dayIdx) => {
        const d = hours.value[DAY_KEYS[dayIdx]]
        if (!d || d.closed) return null
        const open = toMin(d.open)
        const close = toMin(d.close)
        if (open === null || close === null) return null
        return { open, close, crossesMidnight: close <= open }
    }

    // Today's window (handles same-day and past-midnight closing).
    const today = windowFor(now.dayIdx)
    if (today) {
        if (!today.crossesMidnight && now.min >= today.open && now.min < today.close) {
            return { open: true, until: hours.value[DAY_KEYS[now.dayIdx]].close }
        }
        if (today.crossesMidnight && now.min >= today.open) {
            return { open: true, until: hours.value[DAY_KEYS[now.dayIdx]].close }
        }
    }

    // A window opened yesterday and runs past midnight into today.
    const yIdx = (now.dayIdx + 6) % 7
    const yesterday = windowFor(yIdx)
    if (yesterday && yesterday.crossesMidnight && now.min < yesterday.close) {
        return { open: true, until: hours.value[DAY_KEYS[yIdx]].close }
    }

    return { open: false, until: null }
})

const todayKey = computed(() => {
    const now = nowInRestaurantTz()
    return now ? DAY_KEYS[now.dayIdx] : null
})

const deliveryLabel = computed(() => {
    const min = r.value.delivery_time_min
    const max = r.value.delivery_time_max
    if (min && max) return `${min}–${max} ${props.t('minutes')}`
    if (min || max) return `${min || max} ${props.t('minutes')}`
    return ''
})

const minOrderLabel = computed(() => {
    const v = r.value.minimum_order
    if (v === null || v === undefined || v === '') return ''
    const num = Number(v)
    if (Number.isNaN(num)) return ''
    const formatted = new Intl.NumberFormat(props.isAr ? 'ar-EG' : 'en-US').format(num)
    return `${formatted} ${r.value.currency_symbol || ''}`.trim()
})

const hasCoords = computed(() =>
    r.value.latitude != null && r.value.longitude != null
    && !Number.isNaN(Number(r.value.latitude)) && !Number.isNaN(Number(r.value.longitude)),
)
const mapEmbedSrc = computed(() =>
    hasCoords.value ? `https://maps.google.com/maps?q=${r.value.latitude},${r.value.longitude}&z=15&output=embed` : '',
)
const directionsUrl = computed(() => {
    if (hasCoords.value) return `https://www.google.com/maps/dir/?api=1&destination=${r.value.latitude},${r.value.longitude}`
    if (r.value.address) return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(r.value.address)}`
    return ''
})

const description = computed(() => props.localize(r.value, 'description'))

// Only render rows we actually have data for. Escape + body scroll-lock are
// handled centrally by App.vue (hasOverlay / closeTopOverlay), matching the
// other menu overlays.
const dayRows = computed(() =>
    DISPLAY_ORDER
        .map((key) => ({ key, data: hours.value[key] }))
        .filter((row) => row.data && (row.data.closed || (row.data.open && row.data.close))),
)
</script>

<template>
    <Teleport to="body">
        <div class="modal-backdrop" @click.self="emit('close')">
            <div class="info-sheet" role="dialog" aria-modal="true" :aria-label="name">
                <button class="modal-close" :aria-label="t('close')" @click="emit('close')">×</button>

                <header class="info-head">
                    <img v-if="r.logo_url" :src="r.logo_url" :alt="name" />
                    <div v-else class="info-avatar">{{ initial }}</div>
                    <div class="info-head-copy">
                        <h2>{{ name }}</h2>
                        <p v-if="status" class="info-status" :class="status.open ? 'is-open' : 'is-closed'">
                            <span class="status-dot"></span>
                            <template v-if="status.open">
                                {{ t('open_now') }}<template v-if="status.until"> · {{ t('closes') }} {{ formatTime(status.until) }}</template>
                            </template>
                            <template v-else>{{ t('closed_now') }}</template>
                        </p>
                        <p v-else-if="r.opening_hours" class="info-status is-neutral">
                            <span class="status-dot"></span>{{ r.opening_hours }}
                        </p>
                    </div>
                </header>

                <p v-if="description" class="info-desc">{{ description }}</p>

                <div v-if="deliveryLabel || minOrderLabel" class="info-stats">
                    <div v-if="deliveryLabel" class="info-stat">
                        <span class="info-stat-label">{{ t('delivery_time') }}</span>
                        <span class="info-stat-value">{{ deliveryLabel }}</span>
                    </div>
                    <div v-if="minOrderLabel" class="info-stat">
                        <span class="info-stat-label">{{ t('min_order') }}</span>
                        <span class="info-stat-value">{{ minOrderLabel }}</span>
                    </div>
                </div>

                <section v-if="dayRows.length" class="info-block">
                    <h3>{{ t('working_hours') }}</h3>
                    <ul class="hours-list">
                        <li v-for="row in dayRows" :key="row.key" class="hours-row" :class="{ 'is-today': row.key === todayKey }">
                            <span class="hours-day">{{ t('d_' + row.key) }}</span>
                            <span v-if="row.data.closed" class="hours-time is-closed">{{ t('closed') }}</span>
                            <span v-else class="hours-time" dir="ltr">{{ formatTime(row.data.open) }} – {{ formatTime(row.data.close) }}</span>
                        </li>
                    </ul>
                </section>

                <section v-if="r.address || hasCoords" class="info-block">
                    <h3>{{ t('address_contact') }}</h3>
                    <div v-if="hasCoords" class="info-map">
                        <iframe
                            :src="mapEmbedSrc"
                            :title="t('map_location')"
                            loading="lazy"
                            referrerpolicy="no-referrer-when-downgrade"
                            allowfullscreen
                        ></iframe>
                    </div>
                    <p v-if="r.address" class="info-address">{{ r.address }}</p>
                </section>

                <div v-if="directionsUrl || r.phone" class="info-actions">
                    <a v-if="directionsUrl" class="info-btn info-btn--ghost" :href="safeUrl(directionsUrl)" target="_blank" rel="noopener">{{ t('directions') }}</a>
                    <a v-if="r.phone" class="info-btn info-btn--solid" :href="`tel:${r.phone}`">{{ t('call') }}</a>
                </div>
            </div>
        </div>
    </Teleport>
</template>

<style scoped>
.info-sheet {
    background: var(--surface);
    border-radius: 26px;
    width: min(520px, 94vw);
    max-height: 92vh;
    overflow-y: auto;
    position: relative;
    padding: 26px 22px 22px;
    animation: .24s modalIn;
    box-shadow: 0 28px 90px #00000047;
}

.info-head {
    display: flex;
    align-items: center;
    gap: 14px;
    padding-inline-end: 40px;
}

.info-head img, .info-avatar {
    width: 54px;
    height: 54px;
    border-radius: 14px;
    object-fit: cover;
    flex: none;
}

.info-avatar {
    display: grid;
    place-items: center;
    background: var(--accent);
    color: #fff;
    font-size: 22px;
    font-weight: 800;
}

.info-head-copy h2 {
    margin: 0;
    font-size: 20px;
    letter-spacing: -.02em;
}

.info-status {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin: 4px 0 0;
    font-size: 13px;
    font-weight: 700;
}

.info-status .status-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: currentColor;
    flex: none;
}

.info-status.is-open { color: var(--green); }
.info-status.is-closed { color: #b91c1c; }
.info-status.is-neutral { color: var(--muted); font-weight: 600; }

.info-desc {
    color: var(--muted);
    font-size: 13px;
    line-height: 1.7;
    margin: 14px 0 0;
}

.info-stats {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-top: 16px;
}

.info-stat {
    background: var(--cream);
    border: 1px solid var(--line);
    border-radius: 14px;
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.info-stat-label {
    color: var(--muted);
    font-size: 11px;
    font-weight: 600;
}

.info-stat-value {
    font-size: 15px;
    font-weight: 800;
    color: var(--ink);
}

.info-block {
    margin-top: 22px;
}

.info-block h3 {
    margin: 0 0 10px;
    font-size: 15px;
    font-weight: 800;
}

.hours-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.hours-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 9px 12px;
    border-radius: 10px;
    background: var(--cream);
    font-size: 13px;
}

.hours-row.is-today {
    background: var(--accent-soft);
    border: 1px solid var(--accent-border);
    font-weight: 700;
}

.hours-day { font-weight: 700; }
.hours-time { color: var(--muted); }
.hours-row.is-today .hours-time { color: var(--ink); }
.hours-time.is-closed { color: #b91c1c; }

.info-map {
    border-radius: 14px;
    overflow: hidden;
    border: 1px solid var(--line);
    aspect-ratio: 16 / 9;
    background: var(--cream-deep);
}

.info-map iframe {
    width: 100%;
    height: 100%;
    border: 0;
    display: block;
}

.info-address {
    color: var(--muted);
    font-size: 13px;
    line-height: 1.6;
    margin: 10px 0 0;
}

.info-actions {
    display: flex;
    gap: 10px;
    margin-top: 22px;
}

.info-btn {
    flex: 1;
    min-height: 48px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 14px;
    font-size: 15px;
    font-weight: 700;
    text-decoration: none;
    transition: transform .2s, background .2s;
}

.info-btn:hover { transform: translateY(-1px); }

.info-btn--ghost {
    background: var(--cream);
    border: 1px solid var(--line);
    color: var(--ink);
}

.info-btn--solid {
    background: var(--ink);
    color: #fff;
}

@media (width <= 560px) {
    .info-sheet {
        width: 100%;
        max-height: 94vh;
        border-radius: 24px 24px 0 0;
        align-self: end;
    }
}
</style>
