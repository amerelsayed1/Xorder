<script setup>
import { reactive, ref, computed, onMounted, watch, nextTick } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { useAuth } from '@xorder/api-client/auth.js'
import { useMenuLang } from '../../lib/menuLang.js'
import BusinessHoursEditor from '../../components/BusinessHoursEditor.vue'
import GeofenceMap from '../../components/GeofenceMap.vue'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const auth = useAuth()
// Render only the language name fields the client is configured for (single
// default-language field when not bilingual), matching the item/category forms.
const { langs, bilingual } = useMenuLang()

// TEMPORARY — on-site presence enforcement is switched off platform-wide.
// Mirrors platform.presence.geofence_enforcement on the API, which is the real
// gate: the server ignores any saved fence while that is false, so showing the
// editor here would let an owner draw an area that does nothing. Flip both back
// together to restore.
const GEOFENCE_ENABLED = false

const isEdit = computed(() => !!route.params.id)
const backArrow = computed(() => locale.value === 'ar' ? '→' : '←')

const loading = ref(true)
const saving = ref(false)
const errors = ref({})
const blank = () => ({ name_en: '', name_ar: '', address: '', phone: '', whatsapp_number: '', opening_hours: '', business_hours: {}, map_url: '', latitude: null, longitude: null, geofence: null, geofence_enabled: false, require_branch_wifi: false, supported_order_types: [], is_open: true, is_active: true })
const form = reactive(blank())

// POS-BE-005: which order types this branch takes. The till renders one tab per
// entry and PosOrderService refuses anything outside the list — but ONLY when
// the list is non-empty (`$supported !== [] && ! in_array(...)`), so an empty
// array means every type is allowed, not none. The copy below has to say that.
const POS_ORDER_TYPES = ['dine_in', 'takeaway', 'delivery', 'drive_thru']

// Anything already stored that isn't one of the four — in practice `pickup`,
// written by the Super Admin onboarding wizard, where the value mirrors the
// plan's ordering-channel feature keys rather than the till's tabs. Shown as a
// real checkbox rather than preserved invisibly: a hidden entry would make an
// "all types allowed" row silently restrictive.
const legacyOrderTypes = computed(() =>
    (form.supported_order_types || []).filter((tp) => !POS_ORDER_TYPES.includes(tp)))

const orderTypeOptions = computed(() => [...POS_ORDER_TYPES, ...legacyOrderTypes.value])

// Arabic separates a list with ، not a comma.
const listSep = computed(() => (locale.value === 'ar' ? '، ' : ', '))
const orderTypeNames = (list) => list.map((x) => t('order_type.' + x)).join(listSep.value)

function toggleOrderType(tp) {
    const list = form.supported_order_types
    const i = list.indexOf(tp)
    if (i === -1) list.push(tp)
    else list.splice(i, 1)
}

// A fence the backend would enforce: a radius with a real centre + positive
// radius, or a polygon of >= 3 vertices (mirrors App\Support\GeoFence::isEnforceable).
function fenceEnforceable(f) {
    if (!f || typeof f !== 'object') return false
    if (f.type === 'radius') return !!f.center && f.center.lat != null && f.center.lng != null && Number(f.radius) > 0
    const pts = Array.isArray(f.points) ? f.points : (Array.isArray(f) ? f : [])
    return pts.length >= 3
}

// While a branch is loaded into the form we assign the fence programmatically;
// suppress the auto-enable during that so we never override the saved state.
let hydrating = false
// True when the branch already had an enforceable fence on open — its saved
// enabled/disabled choice is authoritative, so we don't auto-flip it.
let fenceExistedOnOpen = false
// True once the admin clicks the toggle this session — an explicit choice we honour.
let geofenceToggledManually = false

// Table-ordering venues are on-premise, so the first time an admin draws a fence
// we default presence-enforcement ON (opt-out). Gated to clients that actually
// run table ordering, and never applied to an existing fence or after the admin
// has made an explicit toggle choice.
watch(() => form.geofence, () => {
    if (hydrating || fenceExistedOnOpen || geofenceToggledManually) return
    if (!auth.hasFeature('table_management')) return
    if (fenceEnforceable(form.geofence)) form.geofence_enabled = true
}, { deep: true })

function toggleGeofence() {
    geofenceToggledManually = true
    form.geofence_enabled = !form.geofence_enabled
}

onMounted(async () => {
    hydrating = true
    if (isEdit.value) {
        try {
            // No single-resource endpoint exists (branches only exposes index),
            // so load the list and pick our branch out of it.
            const { data } = await api.get('api/dashboard/branches')
            const b = (data.data || []).find((x) => String(x.id) === String(route.params.id))
            if (b) Object.assign(form, blank(), {
                name_en: b.name_en || '', name_ar: b.name_ar || '', address: b.address || '',
                phone: b.phone || '', whatsapp_number: b.whatsapp_number || '',
                opening_hours: b.opening_hours || '', business_hours: b.business_hours || {}, map_url: b.map_url || '',
                latitude: b.latitude ?? null, longitude: b.longitude ?? null,
                geofence: b.geofence || null, geofence_enabled: !!b.geofence_enabled,
                require_branch_wifi: !!b.require_branch_wifi,
                supported_order_types: [...(b.supported_order_types || [])],
                is_open: b.is_open, is_active: b.is_active,
            })
            fenceExistedOnOpen = fenceEnforceable(form.geofence)
            await loadPresence()
        } catch (err) { /* fall through to blank form */ }
    }
    loading.value = false
    nextTick(() => { hydrating = false })
})

// Read-only Wi-Fi presence summary. Reporting, not configuration — the signal
// never gates an order, so nothing here is editable and a failure to load just
// hides the card rather than blocking the form.
const presence = ref(null)

async function loadPresence() {
    if (!isEdit.value) return
    try {
        const { data } = await api.get(`api/dashboard/branches/${route.params.id}/presence`)
        presence.value = data.data
    } catch (err) { presence.value = null }
}

// Adding/removing a branch connection saves immediately rather than waiting for
// the form's Save — it is its own endpoint, and folding it into the branch PUT
// would make a half-filled form able to wipe the list.
const savingWifi = ref(false)

// The card reads the caller's address at load time, so after moving onto the
// branch Wi-Fi it is stale until the page is reloaded. Re-fetching is enough to
// pick up the new address (and any overnight learning) without losing whatever
// is half-typed in the branch form above.
const refreshingWifi = ref(false)

async function refreshPresence() {
    if (refreshingWifi.value) return
    refreshingWifi.value = true
    try { await loadPresence() } finally { refreshingWifi.value = false }
}

const currentIpAdded = computed(() => {
    const ip = presence.value?.your_ip
    return !!ip && (presence.value?.manual_ips || []).includes(ip)
})

async function saveConnections(list) {
    if (savingWifi.value) return
    savingWifi.value = true
    try {
        await ensureCsrf()
        const { data } = await api.put(`api/dashboard/branches/${route.params.id}/presence/egress-ips`, { egress_ips: list })
        presence.value = data.data
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { savingWifi.value = false }
}

// Accept the address the branch's own traffic says it moved to: add the new one
// and drop the declared ones nothing is arriving from, so the list tracks
// reality instead of accumulating dead entries that quietly widen what counts
// as "on premises".
function acceptSuggestedConnection() {
    const s = presence.value?.drift?.suggested
    if (!s) return
    const stale = presence.value.drift.stale || []
    const kept = (presence.value.manual_ips || []).filter((ip) => !stale.includes(ip))
    saveConnections([...kept, s.ip])
}

function addCurrentConnection() {
    const ip = presence.value?.your_ip
    if (!ip || currentIpAdded.value) return
    saveConnections([...(presence.value.manual_ips || []), ip])
}

function removeConnection(ip) {
    saveConnections((presence.value.manual_ips || []).filter((x) => x !== ip))
}

// Relative "2h ago" style stamp for the last time the connection was confirmed.
const lastConfirmed = computed(() => {
    const iso = presence.value?.learned_at
    if (!iso) return null
    return new Date(iso).toLocaleDateString(locale.value === 'ar' ? 'ar-EG' : 'en-GB', {
        day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
    })
})

function backToList() { router.push({ name: 'dashboard.branches' }) }

async function save() {
    if (saving.value) return // guard against double-submit (double-click)
    errors.value = {}
    const phoneErrors = collectPhoneErrors(
        { phone: form.phone, whatsapp_number: form.whatsapp_number },
        t('restaurant.phone_invalid'),
    )
    if (Object.keys(phoneErrors).length) { errors.value = phoneErrors; return }
    saving.value = true
    try {
        await ensureCsrf()
        if (isEdit.value) await api.put(`api/dashboard/branches/${route.params.id}`, form)
        else await api.post('api/dashboard/branches', form)
        backToList()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
</script>

<template>
    <div class="max-w-2xl">
        <RouterLink :to="{ name: 'dashboard.branches' }" class="text-sm" style="color:var(--muted)">{{ backArrow }} {{ t('common.back') }}</RouterLink>
        <h1 class="page-title my-3">{{ isEdit ? t('branch.edit') : t('branch.new') }}</h1>

        <div v-if="loading" class="card p-6 space-y-4">
            <Skeleton class="h-10 w-full" />
            <Skeleton class="h-10 w-full" />
            <Skeleton class="h-40 w-full" />
        </div>

        <form v-else @submit.prevent="save" class="space-y-5">
            <div class="card p-6 space-y-4">
                <div class="grid grid-cols-1 gap-3" :class="{ 'sm:grid-cols-2': bilingual }">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" />
                        <FormError :errors="errors" :field="'name_' + lng" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span>
                    <textarea v-model="form.address" rows="2" class="input"></textarea>
                    <FormError :errors="errors" field="address" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span>
                        <input v-model="form.phone" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                        <input v-model="form.whatsapp_number" class="input" dir="ltr" data-en-digits />
                        <FormError :errors="errors" field="whatsapp_number" /></label>
                </div>
                <div class="block">
                    <span class="label">{{ t('restaurant.business_hours') }}</span>
                    <p class="page-sub" style="margin:2px 0 8px">{{ t('restaurant.business_hours_hint') }}</p>
                    <BusinessHoursEditor v-model="form.business_hours" :disabled="auth.isReadOnly" />
                </div>
                <label class="block"><span class="label">{{ t('branch.map_url') }}</span>
                    <input v-model="form.map_url" class="input" dir="ltr" placeholder="https://maps.google.com/…" />
                    <FormError :errors="errors" field="map_url" /></label>

                <!-- Presence geofence: draw the branch area; the toggle turns on
                     the on-site check for table-QR ordering. Hidden while
                     GEOFENCE_ENABLED is false — the API ignores the fence, so
                     drawing one would be a control that does nothing. -->
                <div v-if="GEOFENCE_ENABLED" class="block">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.geofence_enabled }" :disabled="auth.isReadOnly" @click="toggleGeofence"></button>
                        {{ t('branch.geofence_enable') }}
                    </label>
                    <p class="page-sub" style="margin:4px 0 8px">{{ t('branch.geofence_enable_hint') }}</p>
                    <GeofenceMap v-model="form.geofence" :center="{ lat: form.latitude, lng: form.longitude }" :disabled="auth.isReadOnly" />
                    <FormError :errors="errors" field="geofence" />
                </div>

                <!-- Customer Wi-Fi recognition. Read-only reporting: the signal
                     corroborates presence but never gates an order, so there is
                     nothing here to configure. -->
                <div v-if="presence" class="block">
                    <div class="flex items-center justify-between gap-3">
                        <span class="label">{{ t('branch.wifi_title') }}</span>
                        <button type="button" class="text-sm flex items-center gap-1" style="color:var(--muted)"
                            :disabled="refreshingWifi" :title="t('branch.wifi_refresh')" @click="refreshPresence">
                            <Icon name="refresh" :size="14" :class="{ 'animate-spin': refreshingWifi }" />
                            {{ t('branch.wifi_refresh') }}
                        </button>
                    </div>
                    <p class="page-sub" style="margin:4px 0 8px">{{ t('branch.wifi_hint') }}</p>

                    <div class="rounded-xl p-4 text-sm" style="border:1px solid var(--line)">
                        <!-- The on-site check is the prerequisite: without it no
                             scan is ever verified, so nothing can be learned.
                             Only worth saying while that check is something the
                             owner can actually switch on — when it is disabled
                             platform-wide, pointing at it would be a dead end. -->
                        <p v-if="presence.learning_active && !presence.geofence_enabled" style="color:var(--muted)">
                            {{ t('branch.wifi_needs_geofence') }}
                        </p>

                        <template v-else>
                            <div class="flex items-center justify-between gap-3">
                                <span style="color:var(--body)">{{ t('branch.wifi_title') }}</span>
                                <span class="badge" :class="presence.wifi_detected ? 'badge-green' : 'badge-gray'">
                                    <span class="dot"></span>
                                    {{ presence.wifi_detected ? t('branch.wifi_detected') : t('branch.wifi_pending') }}
                                </span>
                            </div>

                            <p v-if="!presence.wifi_detected" style="color:var(--muted);margin-top:8px">
                                {{ presence.learning_active ? t('branch.wifi_pending_hint') : t('branch.wifi_learning_paused') }}
                            </p>

                            <!-- Setup by hand. Deliberately not an "enter your IP
                                 address" field: an owner cannot be expected to
                                 know theirs, but they can open this page on the
                                 branch Wi-Fi, which tells us the same thing. -->
                            <div style="margin-top:14px;padding-top:14px;border-top:1px solid var(--line)">
                                <div class="flex items-center justify-between gap-3 flex-wrap">
                                    <span style="color:var(--body)">{{ t('branch.wifi_connections') }}</span>
                                    <button type="button" class="pill-btn" :disabled="savingWifi || auth.isReadOnly || !presence.your_ip || currentIpAdded"
                                        @click="addCurrentConnection">
                                        {{ savingWifi ? t('branch.wifi_saving') : (currentIpAdded ? t('branch.wifi_already_added') : t('branch.wifi_add_current')) }}
                                    </button>
                                </div>

                                <p v-if="presence.your_ip" style="color:var(--muted);margin-top:6px" >
                                    <span dir="ltr">{{ t('branch.wifi_current_is', { ip: presence.your_ip }) }}</span>
                                </p>

                                <!-- The line appears to have moved. Surfaced for
                                     confirmation, never applied automatically:
                                     a table scan is not proof of presence, so
                                     promoting whatever dominates would be a way
                                     in for anyone patient enough. -->
                                <div v-if="presence.drift.suggested" style="margin-top:12px;padding:10px 12px;border-radius:10px;background:var(--amber-soft)">
                                    <p style="color:var(--amber)">
                                        {{ t('branch.wifi_changed', { ip: presence.drift.suggested.ip, share: presence.drift.suggested.share, days: presence.drift.window_days }) }}
                                    </p>
                                    <button type="button" class="pill-btn" style="margin-top:8px"
                                        :disabled="savingWifi || auth.isReadOnly" @click="acceptSuggestedConnection">
                                        {{ savingWifi ? t('branch.wifi_saving') : t('branch.wifi_use_changed') }}
                                    </button>
                                </div>

                                <ul v-if="presence.manual_ips.length" style="margin-top:10px">
                                    <li v-for="ip in presence.manual_ips" :key="ip"
                                        class="flex items-center justify-between gap-3" style="padding:6px 0">
                                        <span class="flex items-center gap-2 flex-wrap">
                                            <span style="color:var(--body)" dir="ltr">{{ ip }}</span>
                                            <!-- Nothing has arrived from this address all window: almost
                                                 certainly a rotated line, so say so rather than let it sit
                                                 there looking healthy. -->
                                            <span v-if="presence.drift.stale.includes(ip)" class="badge badge-amber">
                                                {{ t('branch.wifi_not_seen') }}
                                            </span>
                                        </span>
                                        <button type="button" class="text-sm" style="color:var(--red)"
                                            :disabled="savingWifi || auth.isReadOnly" @click="removeConnection(ip)">
                                            {{ t('branch.wifi_remove') }}
                                        </button>
                                    </li>
                                </ul>
                                <p v-else style="color:var(--muted);margin-top:10px">{{ t('branch.wifi_none_added') }}</p>

                                <p style="color:var(--muted);margin-top:8px">{{ t('branch.wifi_add_hint') }}</p>
                                <p v-if="presence.learned" style="color:var(--muted);margin-top:6px">{{ t('branch.wifi_learned_note') }}</p>
                                <FormError :errors="errors" field="egress_ips.0" />
                            </div>

                            <template v-if="presence.wifi_detected">
                                <div v-if="lastConfirmed" class="flex items-center justify-between gap-3" style="margin-top:10px">
                                    <span style="color:var(--muted)">{{ t('branch.wifi_last_confirmed') }}</span>
                                    <span style="color:var(--body)" dir="ltr">{{ lastConfirmed }}</span>
                                </div>
                                <div v-if="presence.on_wifi_rate !== null" class="flex items-center justify-between gap-3" style="margin-top:10px">
                                    <span style="color:var(--muted)">{{ t('branch.wifi_rate') }}</span>
                                    <span style="color:var(--body)">{{ presence.on_wifi_rate }}%</span>
                                </div>
                                <!-- Explains the percentage, so it only belongs
                                     here when there is a percentage to explain —
                                     otherwise it reads as a caption for nothing. -->
                                <p v-if="presence.on_wifi_rate !== null" style="color:var(--muted);margin-top:8px">
                                    {{ form.require_branch_wifi
                                        ? t('branch.wifi_rate_hint_enforced', { days: presence.window_days })
                                        : t('branch.wifi_rate_hint', { days: presence.window_days }) }}
                                </p>

                                <!-- Turns the signal into a hard gate. Only offered
                                     once an address is on file, mirroring the server
                                     guard, and it states the cost in the branch's own
                                     measured numbers rather than in the abstract —
                                     the rate here IS the share of diners it keeps. -->
                                <div style="margin-top:14px;padding-top:14px;border-top:1px solid var(--line)">
                                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                                        <button type="button" class="switch" :class="{ on: form.require_branch_wifi }"
                                            :disabled="auth.isReadOnly"
                                            @click="form.require_branch_wifi = !form.require_branch_wifi"></button>
                                        {{ t('branch.wifi_require') }}
                                    </label>
                                    <p style="color:var(--muted);margin-top:6px">{{ t('branch.wifi_require_hint') }}</p>
                                    <div v-if="form.require_branch_wifi" style="margin-top:10px;padding:10px 12px;border-radius:10px;background:var(--amber-soft)">
                                        <p style="color:var(--amber)">
                                            {{ presence.on_wifi_rate !== null
                                                ? t('branch.wifi_require_warn_rate', { rate: presence.on_wifi_rate, blocked: 100 - presence.on_wifi_rate, days: presence.window_days })
                                                : t('branch.wifi_require_warn') }}
                                        </p>
                                    </div>
                                    <FormError :errors="errors" field="require_branch_wifi" />
                                </div>
                            </template>
                        </template>
                    </div>
                </div>

                <!-- POS-BE-005: the order types this branch's tills offer.
                     Unticked-everything is the permissive state, not the empty
                     one — the server only narrows when the list is non-empty —
                     so the hint says "all allowed" rather than "none".

                     Edit only: StoreBranchRequest does not (yet) validate the
                     field, so a choice made on the create form would be dropped
                     by `validated()` without a word. A new branch starts at []
                     — every type allowed — and the picker appears the moment it
                     exists. -->
                <div v-if="isEdit" class="block">
                    <span class="label">{{ t('branch.order_types') }}</span>
                    <p class="page-sub" style="margin:2px 0 8px">{{ t('branch.order_types_hint') }}</p>
                    <div class="flex flex-wrap gap-x-5 gap-y-2">
                        <label v-for="tp in orderTypeOptions" :key="tp" class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)">
                            <input type="checkbox" class="h-4 w-4" :disabled="auth.isReadOnly"
                                :checked="form.supported_order_types.includes(tp)" @change="toggleOrderType(tp)" />
                            {{ t('order_type.' + tp) }}
                        </label>
                    </div>
                    <p class="text-sm" style="color:var(--muted);margin-top:8px">
                        {{ form.supported_order_types.length
                            ? t('branch.order_types_some', { types: orderTypeNames(form.supported_order_types) })
                            : t('branch.order_types_all') }}
                    </p>
                    <p v-if="legacyOrderTypes.length" class="text-xs" style="color:var(--muted);margin-top:6px">
                        {{ t('branch.order_types_legacy', { types: orderTypeNames(legacyOrderTypes) }) }}
                    </p>
                    <FormError :errors="errors" field="supported_order_types" />
                    <!-- The `.*` rule reports per-entry, so a value the server
                         does not accept lands on the indexed key, not the array. -->
                    <FormError :errors="errors" field="supported_order_types.0" />
                </div>

                <div class="flex items-center gap-6">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_open }" @click="form.is_open = !form.is_open"></button>
                        {{ t('branch.open') }}
                    </label>
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.is_active }" @click="form.is_active = !form.is_active"></button>
                        {{ t('common.active') }}
                    </label>
                </div>
            </div>

            <div class="flex justify-end gap-2">
                <RouterLink :to="{ name: 'dashboard.branches' }" class="btn btn-ghost">{{ t('common.cancel') }}</RouterLink>
                <button type="submit" :disabled="saving || auth.isReadOnly" class="btn btn-accent">
                    <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                    {{ saving ? t('common.saving') : t('common.save') }}
                </button>
            </div>
        </form>
    </div>
</template>
