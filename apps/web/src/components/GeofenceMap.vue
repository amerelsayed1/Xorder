<script setup>
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'

/**
 * Draw a branch's presence area on an OpenStreetMap map, as either:
 *  - a polygon: tap to drop vertices; tap a vertex to remove it, or
 *  - a radius: tap to place the centre, then set the radius in metres.
 * v-model is a self-describing object:
 *   { type:'polygon', points:[{lat,lng},...] }
 *   { type:'radius',  center:{lat,lng}, radius:<metres> }
 * No API key (OSM tiles), no marker-image assets (circleMarkers only).
 */
const props = defineProps({
    modelValue: { type: Object, default: null },
    center: { type: Object, default: null }, // branch pin, used as the empty-state centre
    disabled: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue'])
const { t } = useI18n()

const ACCENT = '#f89a06'
const DEFAULT_CENTER = [30.0444, 31.2357]

const el = ref(null)
const mode = ref(props.modelValue?.type === 'radius' ? 'radius' : 'polygon')
const pointCount = ref(0)
const radiusM = ref(props.modelValue?.type === 'radius' ? Number(props.modelValue.radius) || 150 : 150)
const locating = ref(false)
const locateMsg = ref('')
// "Walk the perimeter": record the branch outline by walking it. While active a
// vertex is dropped automatically each time the owner moves MIN_STEP_M, fuzzy
// fixes (worse than MAX_ACCURACY_M) are ignored so GPS jitter can't pollute it.
const recording = ref(false)
const recAccuracy = ref(null)
// Corner capture: stand at each corner, tap once — a good GPS fix (best of a
// short sample) is dropped as a vertex, and the vertices connect into the shape.
const capturing = ref(false)
const captureAccuracy = ref(null)
const MIN_STEP_M = 5
const MAX_ACCURACY_M = 30
const CORNER_SAMPLE_MS = 3000
const CORNER_GOOD_ACCURACY_M = 8

let map = null
let watchId = null
let lastFix = null
let layers = []
let points = props.modelValue?.type === 'polygon' && Array.isArray(props.modelValue.points)
    ? props.modelValue.points.map((p) => ({ lat: Number(p.lat), lng: Number(p.lng) }))
    : []
let radiusCenter = props.modelValue?.type === 'radius' && props.modelValue.center
    ? { lat: Number(props.modelValue.center.lat), lng: Number(props.modelValue.center.lng) }
    : null

function clearLayers() {
    layers.forEach((l) => l.remove())
    layers = []
}

function commit() {
    let value = null
    if (mode.value === 'polygon') {
        pointCount.value = points.length
        if (points.length) value = { type: 'polygon', points: points.map((p) => ({ lat: p.lat, lng: p.lng })) }
    } else if (radiusCenter) {
        value = { type: 'radius', center: { lat: radiusCenter.lat, lng: radiusCenter.lng }, radius: Number(radiusM.value) }
    }
    emit('update:modelValue', value)
    render()
}

function render() {
    if (!map) return
    clearLayers()

    if (mode.value === 'polygon') {
        if (points.length >= 2) {
            layers.push(L.polygon(points.map((p) => [p.lat, p.lng]), { color: ACCENT, weight: 2, fillColor: ACCENT, fillOpacity: 0.15 }).addTo(map))
        }
        points.forEach((p, i) => {
            const m = L.circleMarker([p.lat, p.lng], { radius: 6, color: ACCENT, fillColor: '#fff', fillOpacity: 1, weight: 2 })
            if (!props.disabled) m.on('click', (e) => { L.DomEvent.stop(e); points.splice(i, 1); commit() })
            m.addTo(map)
            layers.push(m)
        })
    } else if (radiusCenter) {
        layers.push(L.circle([radiusCenter.lat, radiusCenter.lng], { radius: Number(radiusM.value), color: ACCENT, weight: 2, fillColor: ACCENT, fillOpacity: 0.15 }).addTo(map))
        layers.push(L.circleMarker([radiusCenter.lat, radiusCenter.lng], { radius: 6, color: ACCENT, fillColor: '#fff', fillOpacity: 1, weight: 2 }).addTo(map))
    }
}

function onMapClick(e) {
    if (props.disabled) return
    if (mode.value === 'polygon') {
        points.push({ lat: e.latlng.lat, lng: e.latlng.lng })
    } else {
        radiusCenter = { lat: e.latlng.lat, lng: e.latlng.lng }
    }
    commit()
}

function setMode(next) {
    if (props.disabled || mode.value === next) return
    mode.value = next
    commit()
}

function onRadiusInput() {
    radiusM.value = Math.min(20000, Math.max(10, Number(radiusM.value) || 10))
    if (radiusCenter) commit(); else render()
}

// Jump the map to the admin's current GPS. In radius mode this also drops the
// centre where they're standing (they're usually at the branch); in polygon
// mode it just recentres so they can draw around themselves.
function locateMe() {
    if (props.disabled || !navigator.geolocation) { locateMsg.value = t('branch.geofence_locate_denied'); return }
    locating.value = true
    locateMsg.value = ''
    navigator.geolocation.getCurrentPosition(
        (pos) => {
            locating.value = false
            const { latitude, longitude } = pos.coords
            if (map) map.setView([latitude, longitude], 17)
            if (mode.value === 'radius') { radiusCenter = { lat: latitude, lng: longitude }; commit() }
        },
        () => { locating.value = false; locateMsg.value = t('branch.geofence_locate_denied') },
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    )
}

// Great-circle distance in metres — how far the walker moved since the last
// dropped vertex, so standing still doesn't spam points and a steady walk traces.
function metresBetween(a, b) {
    const R = 6371000, toRad = (d) => d * Math.PI / 180
    const dLat = toRad(b.lat - a.lat), dLng = toRad(b.lng - a.lng)
    const s = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)))
}

function addFix(lat, lng) {
    points.push({ lat, lng })
    lastFix = { lat, lng }
    commit()
}

// Start tracing: watch GPS and auto-drop a vertex every MIN_STEP_M of movement.
function startWalk() {
    if (props.disabled || !navigator.geolocation) { locateMsg.value = t('branch.geofence_locate_denied'); return }
    if (mode.value !== 'polygon') { mode.value = 'polygon'; commit() }
    locateMsg.value = ''
    recAccuracy.value = null
    recording.value = true
    // Continue from wherever the current outline left off.
    lastFix = points.length ? points[points.length - 1] : null
    watchId = navigator.geolocation.watchPosition(
        (pos) => {
            const { latitude, longitude, accuracy } = pos.coords
            recAccuracy.value = Math.round(accuracy)
            if (map) map.panTo([latitude, longitude])
            if (accuracy > MAX_ACCURACY_M) return // too fuzzy to trust — skip
            const fix = { lat: latitude, lng: longitude }
            if (!lastFix || metresBetween(lastFix, fix) >= MIN_STEP_M) addFix(latitude, longitude)
        },
        () => { locateMsg.value = t('branch.geofence_locate_denied'); stopWalk() },
        { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 },
    )
}

// Force a vertex at the current spot — for a sharp corner between auto-drops.
function dropPoint() {
    if (!recording.value || !navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
        (pos) => addFix(pos.coords.latitude, pos.coords.longitude),
        () => {},
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
    )
}

function stopWalk() {
    recording.value = false
    if (watchId !== null && navigator.geolocation) navigator.geolocation.clearWatch(watchId)
    watchId = null
    lastFix = null
    if (map && points.length >= 2) map.fitBounds(L.polygon(points.map((p) => [p.lat, p.lng])).getBounds(), { padding: [24, 24] })
}

// Capture ONE corner at the owner's current spot: sample GPS for a few seconds,
// keep the tightest fix, and drop it as a vertex. Far more accurate than a
// walked trace — the owner places each corner deliberately, and the polygon
// connects them, so the outline hugs the real building instead of ballooning.
function captureCorner() {
    if (props.disabled || capturing.value || !navigator.geolocation) {
        if (!navigator.geolocation) locateMsg.value = t('branch.geofence_locate_denied')
        return
    }
    if (mode.value !== 'polygon') { mode.value = 'polygon'; commit() }
    locateMsg.value = ''
    captureAccuracy.value = null
    capturing.value = true

    let best = null
    let done = false
    let id = null
    const finish = () => {
        if (done) return
        done = true
        if (id !== null) navigator.geolocation.clearWatch(id)
        capturing.value = false
        if (best) addFix(best.lat, best.lng)
        else locateMsg.value = t('branch.geofence_locate_denied')
    }
    id = navigator.geolocation.watchPosition(
        (pos) => {
            const { latitude, longitude, accuracy } = pos.coords
            captureAccuracy.value = Math.round(accuracy)
            if (map) map.panTo([latitude, longitude])
            if (!best || accuracy < best.accuracy) best = { lat: latitude, lng: longitude, accuracy }
            if (best.accuracy <= CORNER_GOOD_ACCURACY_M) finish() // already precise — stop early
        },
        () => finish(),
        { enableHighAccuracy: true, timeout: CORNER_SAMPLE_MS + 3000, maximumAge: 0 },
    )
    setTimeout(finish, CORNER_SAMPLE_MS)
}

function undo() { points.pop(); commit() }
function clearAll() { points = []; radiusCenter = null; commit() }
defineExpose({ undo, clearAll })

onMounted(async () => {
    const seed = radiusCenter ? [radiusCenter.lat, radiusCenter.lng]
        : (points[0] ? [points[0].lat, points[0].lng]
            : (props.center && Number.isFinite(Number(props.center.lat)) ? [Number(props.center.lat), Number(props.center.lng)] : DEFAULT_CENTER))
    map = L.map(el.value, { zoomControl: true }).setView(seed, 16)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map)
    if (!props.disabled) map.on('click', onMapClick)

    pointCount.value = points.length
    render()
    if (points.length >= 2) map.fitBounds(L.polygon(points.map((p) => [p.lat, p.lng])).getBounds(), { padding: [24, 24] })
    await nextTick()
    setTimeout(() => map && map.invalidateSize(), 60)
})

onBeforeUnmount(() => {
    if (watchId !== null && navigator.geolocation) navigator.geolocation.clearWatch(watchId)
    if (map) { map.remove(); map = null }
})
</script>

<template>
    <div class="geofence">
        <div class="geofence__modes">
            <button type="button" class="geofence__mode" :class="{ active: mode === 'polygon' }" :disabled="disabled" @click="setMode('polygon')">{{ t('branch.geofence_type_polygon') }}</button>
            <button type="button" class="geofence__mode" :class="{ active: mode === 'radius' }" :disabled="disabled" @click="setMode('radius')">{{ t('branch.geofence_type_radius') }}</button>
        </div>

        <div class="geofence__mapwrap">
            <div ref="el" class="geofence__map"></div>
            <button
                type="button"
                class="geofence__locate"
                :class="{ busy: locating }"
                :disabled="disabled || locating"
                :title="t('branch.geofence_locate')"
                :aria-label="t('branch.geofence_locate')"
                @click="locateMe"
            >
                <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <circle cx="12" cy="12" r="3.2" />
                    <path d="M12 2v3.4M12 18.6V22M2 12h3.4M18.6 12H22" />
                </svg>
            </button>
        </div>

        <div v-if="mode === 'polygon'" class="geofence__bar">
            <template v-if="!recording">
                <span class="geofence__count">{{ t('branch.geofence_points', { n: pointCount }) }}</span>
                <span class="flex-1"></span>
                <button v-if="!disabled" type="button" class="btn btn-accent btn-sm" :disabled="capturing" @click="captureCorner">
                    <span v-if="capturing">{{ t('branch.geofence_capturing') }}<template v-if="captureAccuracy != null"> ±{{ captureAccuracy }}m</template></span>
                    <span v-else>{{ t('branch.geofence_add_corner') }}</span>
                </button>
                <button v-if="!disabled" type="button" class="btn btn-ghost btn-sm" @click="startWalk">{{ t('branch.geofence_walk') }}</button>
                <button v-if="!disabled" type="button" class="btn btn-ghost btn-sm" :disabled="!pointCount" @click="undo">{{ t('branch.geofence_undo') }}</button>
                <button v-if="!disabled" type="button" class="btn btn-ghost btn-sm" :disabled="!pointCount" @click="clearAll">{{ t('branch.geofence_clear') }}</button>
            </template>
            <template v-else>
                <span class="geofence__count geofence__rec">
                    <span class="geofence__rec-dot"></span>{{ t('branch.geofence_walking', { n: pointCount }) }}<template v-if="recAccuracy != null"> · ±{{ recAccuracy }}m</template>
                </span>
                <span class="flex-1"></span>
                <button type="button" class="btn btn-ghost btn-sm" @click="dropPoint">{{ t('branch.geofence_drop') }}</button>
                <button type="button" class="btn btn-accent btn-sm" @click="stopWalk">{{ t('branch.geofence_finish') }}</button>
            </template>
        </div>
        <div v-else class="geofence__bar">
            <span class="geofence__count">{{ t('branch.geofence_radius_label') }}</span>
            <input type="range" min="20" max="2000" step="10" v-model.number="radiusM" :disabled="disabled" class="geofence__slider" @input="onRadiusInput" />
            <input type="number" min="10" max="20000" v-model.number="radiusM" :disabled="disabled" class="geofence__radius-input" @input="onRadiusInput" />
            <span class="geofence__count">{{ t('branch.geofence_meters') }}</span>
        </div>

        <p class="page-sub" style="margin-top:6px">{{ recording ? t('branch.geofence_walk_hint') : (mode === 'polygon' ? t('branch.geofence_hint') : t('branch.geofence_radius_hint')) }}</p>
        <p v-if="locateMsg" class="geofence__locate-msg">{{ locateMsg }}</p>
    </div>
</template>

<style scoped>
.geofence__modes { display: flex; gap: 6px; margin-bottom: 8px; }
.geofence__mode {
    flex: 1; padding: 8px 10px; font-size: 13px; font-weight: 600;
    border: 1px solid var(--line); border-radius: 10px;
    background: var(--surface, #fff); color: var(--body); cursor: pointer;
}
.geofence__mode.active { border-color: var(--accent); background: var(--accent-soft); color: var(--accent); }
.geofence__mapwrap { position: relative; }
.geofence__map {
    height: 280px; width: 100%; border-radius: 12px;
    border: 1px solid var(--line); overflow: hidden; z-index: 0;
}
.geofence__locate {
    position: absolute; top: 10px; inset-inline-end: 10px; z-index: 500;
    display: inline-flex; align-items: center; justify-content: center;
    width: 34px; height: 34px; border-radius: 9px;
    border: 1px solid var(--line); background: var(--surface, #fff);
    color: var(--accent); cursor: pointer; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
}
.geofence__locate:hover { background: var(--accent-soft); }
.geofence__locate:disabled { cursor: default; }
.geofence__locate.busy svg { animation: geofence-spin 0.8s linear infinite; }
.geofence__locate-msg { font-size: 12px; color: var(--danger, #dc2626); margin-top: 4px; }
@keyframes geofence-spin { to { transform: rotate(360deg); } }
.geofence__bar { display: flex; align-items: center; gap: 8px; margin-top: 8px; flex-wrap: wrap; }
.geofence__count { font-size: 12px; color: var(--muted); white-space: nowrap; }
.geofence__rec { display: inline-flex; align-items: center; gap: 6px; color: #dc2626; font-weight: 600; }
.geofence__rec-dot { width: 8px; height: 8px; border-radius: 50%; background: #dc2626; animation: geofence-pulse 1s ease-in-out infinite; }
@keyframes geofence-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.25; } }
@media (prefers-reduced-motion: reduce) { .geofence__rec-dot { animation: none; } }
.geofence__slider { flex: 1; accent-color: var(--accent); }
.geofence__radius-input { width: 84px; }
.btn-sm { padding: 5px 10px; font-size: 12px; }
</style>
