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
const locateMsgWarn = ref(false)
// Accuracy of the newest fix from the live watch, in metres — shown while
// walking or capturing so the owner can watch the fix tighten.
const gpsAccuracy = ref(null)
// "Walk the perimeter": record the branch outline by walking it. While active a
// vertex is dropped automatically each time the owner moves MIN_STEP_M, fuzzy
// fixes (worse than MAX_ACCURACY_M) are ignored so GPS jitter can't pollute it.
const recording = ref(false)
// Corner capture: stand at each corner, tap once — the tightest fix of a short
// sample is dropped as a vertex, and the vertices connect into the shape.
const capturing = ref(false)

const MIN_STEP_M = 5
const MAX_ACCURACY_M = 30
// A phone whose GPS has been idle indoors routinely needs 10–20s to hand back
// its first satellite fix, so a capture waits that long for one instead of
// declaring failure after a couple of seconds. It settles as soon as the fix is
// tight enough, so a warm GPS still feels instant.
const CORNER_MIN_SAMPLE_MS = 2500
const CORNER_MAX_SAMPLE_MS = 25000
const CORNER_GOOD_ACCURACY_M = 8
const CORNER_COARSE_ACCURACY_M = 35
// Keep the watch alive between corners: the cold start is the expensive part, so
// the walk to the next corner should not pay it again.
const GPS_WARM_MS = 120000
const FIX_FRESH_MS = 10000

let map = null
let watchId = null
let warmTimer = null
let capture = null // in-flight corner capture: { best, minAt, timer }
let latest = null // newest fix from the watch: { lat, lng, accuracy, at }
let lastFix = null // last vertex dropped while walking
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

function setMsg(text, warn = false) { locateMsg.value = text; locateMsgWarn.value = warn }
function clearMsg() { locateMsg.value = ''; locateMsgWarn.value = false }

// Jump the map to the admin's current GPS. In radius mode this also drops the
// centre where they're standing (they're usually at the branch); in polygon
// mode it just recentres so they can draw around themselves.
function locateMe() {
    if (props.disabled || !navigator.geolocation) { setMsg(t('branch.geofence_locate_denied')); return }
    locating.value = true
    clearMsg()
    navigator.geolocation.getCurrentPosition(
        (pos) => {
            locating.value = false
            const { latitude, longitude } = pos.coords
            if (map) map.setView([latitude, longitude], 17)
            if (mode.value === 'radius') { radiusCenter = { lat: latitude, lng: longitude }; commit() }
        },
        (err) => {
            locating.value = false
            setMsg(err?.code === 1 ? t('branch.geofence_locate_denied') : t('branch.geofence_locate_failed'))
        },
        { enableHighAccuracy: true, timeout: 25000, maximumAge: 0 },
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

/* ── GPS layer ────────────────────────────────────────────────────────────────
 * One watch feeds both the walk recorder and corner capture. It is started on
 * demand and left running for a while after each use, because what costs time is
 * acquiring the first satellite fix, not keeping one. */

function onFix(pos) {
    const { latitude, longitude, accuracy } = pos.coords
    latest = { lat: latitude, lng: longitude, accuracy, at: Date.now() }
    gpsAccuracy.value = Math.round(accuracy)
    if (map && (recording.value || capturing.value)) map.panTo([latitude, longitude])

    if (capture) {
        if (!capture.best || accuracy < capture.best.accuracy) capture.best = { lat: latitude, lng: longitude, accuracy }
        // Settle early once the fix is tight — but never before the minimum
        // sample, since the first reading a phone offers is often optimistic.
        if (capture.best.accuracy <= CORNER_GOOD_ACCURACY_M && Date.now() >= capture.minAt) finishCapture()
    }

    if (recording.value) {
        if (accuracy > MAX_ACCURACY_M) return // too fuzzy to trust — skip
        const fix = { lat: latitude, lng: longitude }
        if (!lastFix || metresBetween(lastFix, fix) >= MIN_STEP_M) addFix(latitude, longitude)
    }
}

// Only a denied permission is terminal. POSITION_UNAVAILABLE / TIMEOUT are
// routine indoors and usually transient, so they must not abort a capture that
// would have succeeded a few seconds later — the sampling window decides.
function onGpsError(err) {
    if (err?.code !== 1) return
    setMsg(t('branch.geofence_locate_denied'))
    if (capturing.value) endCapture()
    if (recording.value) recording.value = false
    stopGps()
}

function ensureGps() {
    if (!navigator.geolocation) { setMsg(t('branch.geofence_locate_denied')); return false }
    if (warmTimer !== null) { clearTimeout(warmTimer); warmTimer = null }
    if (watchId === null) {
        watchId = navigator.geolocation.watchPosition(onFix, onGpsError, {
            enableHighAccuracy: true, timeout: CORNER_MAX_SAMPLE_MS, maximumAge: 0,
        })
    }
    return true
}

function stopGps() {
    if (watchId !== null && navigator.geolocation) navigator.geolocation.clearWatch(watchId)
    watchId = null
    if (warmTimer !== null) { clearTimeout(warmTimer); warmTimer = null }
    gpsAccuracy.value = null
    latest = null
}

// Hold the fix for the walk to the next corner, then release the radio.
function keepWarm() {
    if (recording.value || capturing.value || watchId === null) return
    if (warmTimer !== null) clearTimeout(warmTimer)
    warmTimer = setTimeout(stopGps, GPS_WARM_MS)
}

// Start tracing: watch GPS and auto-drop a vertex every MIN_STEP_M of movement.
function startWalk() {
    if (props.disabled || !ensureGps()) return
    if (mode.value !== 'polygon') { mode.value = 'polygon'; commit() }
    clearMsg()
    recording.value = true
    // Continue from wherever the current outline left off.
    lastFix = points.length ? points[points.length - 1] : null
}

// Force a vertex at the current spot — for a sharp corner between auto-drops.
function dropPoint() {
    if (!recording.value) return
    if (latest && Date.now() - latest.at <= FIX_FRESH_MS) addFix(latest.lat, latest.lng)
}

function stopWalk() {
    recording.value = false
    lastFix = null
    keepWarm()
    if (map && points.length >= 2) map.fitBounds(L.polygon(points.map((p) => [p.lat, p.lng])).getBounds(), { padding: [24, 24] })
}

// Capture ONE corner at the owner's current spot: sample GPS, keep the tightest
// fix, and drop it as a vertex. Far more accurate than a walked trace — the
// owner places each corner deliberately, and the polygon connects them, so the
// outline hugs the real building instead of ballooning.
function captureCorner() {
    if (props.disabled || capturing.value || !ensureGps()) return
    if (mode.value !== 'polygon') { mode.value = 'polygon'; commit() }
    clearMsg()
    capture = {
        best: null,
        minAt: Date.now() + CORNER_MIN_SAMPLE_MS,
        timer: setTimeout(finishCapture, CORNER_MAX_SAMPLE_MS),
    }
    capturing.value = true
}

function endCapture() {
    if (capture?.timer) clearTimeout(capture.timer)
    capture = null
    capturing.value = false
    keepWarm()
}

function finishCapture() {
    if (!capture) return
    const best = capture.best
    endCapture()
    if (!best) { setMsg(t('branch.geofence_locate_failed')); return }
    addFix(best.lat, best.lng)
    // Still accept a coarse fix — but say so, so a corner that lands in the
    // street can be undone rather than silently deforming the fence.
    if (best.accuracy > CORNER_COARSE_ACCURACY_M) setMsg(t('branch.geofence_corner_coarse', { n: Math.round(best.accuracy) }), true)
}

function cancelCapture() { endCapture() }

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
    if (capture?.timer) clearTimeout(capture.timer)
    capture = null
    stopGps()
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
                <span v-if="capturing" class="geofence__count geofence__rec">
                    <span class="geofence__rec-dot"></span>{{ t('branch.geofence_capturing') }}<template v-if="gpsAccuracy != null"> · ±{{ gpsAccuracy }}m</template>
                </span>
                <span v-else class="geofence__count">{{ t('branch.geofence_points', { n: pointCount }) }}</span>
                <span class="flex-1"></span>
                <template v-if="!disabled && capturing">
                    <button type="button" class="btn btn-ghost btn-sm" @click="cancelCapture">{{ t('branch.geofence_capture_cancel') }}</button>
                </template>
                <template v-else-if="!disabled">
                    <button type="button" class="btn btn-accent btn-sm" @click="captureCorner">{{ t('branch.geofence_add_corner') }}</button>
                    <button type="button" class="btn btn-ghost btn-sm" @click="startWalk">{{ t('branch.geofence_walk') }}</button>
                    <button type="button" class="btn btn-ghost btn-sm" :disabled="!pointCount" @click="undo">{{ t('branch.geofence_undo') }}</button>
                    <button type="button" class="btn btn-ghost btn-sm" :disabled="!pointCount" @click="clearAll">{{ t('branch.geofence_clear') }}</button>
                </template>
            </template>
            <template v-else>
                <span class="geofence__count geofence__rec">
                    <span class="geofence__rec-dot"></span>{{ t('branch.geofence_walking', { n: pointCount }) }}<template v-if="gpsAccuracy != null"> · ±{{ gpsAccuracy }}m</template>
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

        <p class="page-sub" style="margin-top:6px">{{ recording ? t('branch.geofence_walk_hint') : (capturing ? t('branch.geofence_capture_hint') : (mode === 'polygon' ? t('branch.geofence_hint') : t('branch.geofence_radius_hint'))) }}</p>
        <p v-if="locateMsg" class="geofence__locate-msg" :class="{ 'geofence__locate-msg--warn': locateMsgWarn }">{{ locateMsg }}</p>
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
.geofence__locate-msg--warn { color: var(--warn, #b45309); }
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
