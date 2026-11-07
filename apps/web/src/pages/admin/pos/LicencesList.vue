<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { withMinDuration } from '../../../lib/minLoading.js'

const router = useRouter()
const { t, locale } = useI18n()

const rows = ref([])
const restaurants = ref([])
const loading = ref(true)
const failed = ref(false)
const restaurantId = ref('')
const state = ref('')
// Cloud and offline licences share one list — an operator asking "whose
// licence expires next?" should not have to ask it twice.
const kind = ref('')
// The operator's own status (R2): "who is suspended?" is a server-side filter.
const opStatus = ref('')
const search = ref('')

// Mirrors PosLicence::state() on the server. `superseded` is deliberately
// listed: a renewed licence is still a record worth finding, not a deletion.
const STATES = ['active', 'expiring_soon', 'in_grace', 'expired', 'pending', 'revoked', 'superseded']

const filtered = computed(() => state.value ? rows.value.filter((l) => l.state === state.value) : rows.value)

const badge = (s) => ({
    active: 'badge-green',
    expiring_soon: 'badge-amber',
    in_grace: 'badge-amber',
    expired: 'badge-red',
    revoked: 'badge-red',
    pending: 'badge-gray',
    superseded: 'badge-gray',
}[s] || 'badge-gray')

// An offline licence has no tenant to name, so the customer on the licence
// itself is the client. The server resolves the same thing into `client_name`;
// the tenant's own localised names are preferred when there IS a tenant.
const clientName = (l) => l.restaurant
    ? (locale.value === 'ar' ? (l.restaurant.name_ar || l.restaurant.name_en) : (l.restaurant.name_en || l.restaurant.name_ar)) || l.restaurant.slug
    : (l.client_name || '—')

const dateOf = (iso) => iso ? new Date(iso).toLocaleDateString(locale.value === 'ar' ? 'ar-EG' : 'en-GB') : '—'

// A licence sold outright reports no expiry at all — a countdown to the 2099
// sentinel it actually stores is a number nobody should read.
const expiryOf = (l) => l.lifetime ? t('licence.lifetime_short') : dateOf(l.expires_at)

// Quick actions. Revoke stops future trade (weakly — see the notice above);
// delete is CLEANUP and the server refuses it for anything still permitting
// trade, so the buttons mirror that split: live rows offer revoke, dead rows
// offer delete. Owner decision, 2026-09-05.
const isLive = (l) => !['revoked', 'superseded', 'expired'].includes(l.state)
const acting = ref(null)

// Suspend / resume (R2) act on the online path only, and only on a row that is
// still live — the server refuses a revoked or superseded one. A force-expired
// licence is held the same way as a suspended one: `state` still reads its
// dates (often "Active"), so `status` is what decides that it offers Resume.
const isRecord = (l) => ['revoked', 'superseded'].includes(l.state)
const isHeld = (l) => l.status === 'suspended' || l.status === 'expired'
// A signed-file licence never asks the platform, so a status set here would
// be a decision no till ever hears — not offered at all.
const isOnline = (l) => (l.enforcement || 'online') === 'online'

async function quickSuspend(l) {
    const ok = await confirm({
        title: t('licence.suspend_title'),
        message: t('licence.suspend_subtitle'),
        confirmText: t('licence.suspend'),
        danger: true,
    })
    if (!ok) return
    await patchRow(l, 'suspend')
}

async function quickResume(l) {
    const ok = await confirm({
        title: t('licence.resume_title'),
        message: t('licence.resume_message'),
        confirmText: t('licence.resume'),
    })
    if (!ok) return
    await patchRow(l, 'resume')
}

async function patchRow(l, action) {
    acting.value = l.id
    try {
        const { data } = await api.post(`api/admin/pos/licences/${l.id}/${action}`, {})
        rows.value = rows.value.map((x) => (x.id === l.id ? data.data : x))
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    } finally {
        acting.value = null
    }
}

async function quickRevoke(l) {
    const ok = await confirm({
        title: t('licence.revoke_title'),
        message: t('licence.revoke_message'),
        confirmText: t('licence.revoke'),
        danger: true,
    })
    if (!ok) return
    acting.value = l.id
    try {
        // The endpoint returns the updated record precisely so the row can be
        // patched in place — refetching the whole list (and flashing its
        // skeletons) for a one-row change reads as a page reload.
        const { data } = await api.post(`api/admin/pos/licences/${l.id}/revoke`, {})
        rows.value = rows.value.map((x) => (x.id === l.id ? data.data : x))
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    } finally {
        acting.value = null
    }
}

async function quickDelete(l) {
    const ok = await confirm({
        title: t('licence.delete_title'),
        message: t('licence.delete_message', { ref: l.licence_ref }),
        confirmText: t('licence.delete'),
        danger: true,
    })
    if (!ok) return
    acting.value = l.id
    try {
        await api.delete(`api/admin/pos/licences/${l.id}`)
        rows.value = rows.value.filter((x) => x.id !== l.id)
    } catch (err) {
        alert(err?.response?.data?.message || t('common.error'))
    } finally {
        acting.value = null
    }
}

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [list, rest] = await withMinDuration(Promise.all([
            api.get('api/admin/pos/licences', {
                params: {
                    restaurant_id: restaurantId.value || undefined,
                    kind: kind.value || undefined,
                    status: opStatus.value || undefined,
                    search: search.value || undefined,
                    per_page: 100,
                },
            }),
            restaurants.value.length ? Promise.resolve(null) : api.get('api/admin/restaurants'),
        ]))
        rows.value = list.data.data
        if (rest) restaurants.value = rest.data.data
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Display-only helpers for the layout below; none of them feed a request.
// Tone drives the row's edge stripe and the expiry colour so state reads before
// the badge is read. A held (suspended / force-expired) online licence is red
// whatever its dates say, matching the badge it shows.
const toneOf = (l) => {
    if (isHeld(l) && !isRecord(l)) return 'red'
    return { active: 'green', expiring_soon: 'amber', in_grace: 'amber', expired: 'red', revoked: 'red' }[l.state] || 'gray'
}
// Counts per state across the loaded rows, attention states first. Zero counts
// are dropped. A chip sets the same `state` filter as the select beside it.
const CHIP_ORDER = ['expired', 'in_grace', 'expiring_soon', 'revoked', 'active', 'pending', 'superseded']
const stateChips = computed(() => CHIP_ORDER
    .map((s) => ({ key: s, count: rows.value.filter((l) => l.state === s).length }))
    .filter((c) => c.count > 0))
const toggleState = (s) => { state.value = state.value === s ? '' : s }
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0">
                <h1 class="page-title">{{ t('nav.licences') }}</h1>
                <p class="page-sub" style="color:var(--body)">{{ t('licence.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.licences.new' }" class="btn btn-accent new-btn">
                <Icon name="plus" :size="16" />{{ t('licence.new_client') }}
            </RouterLink>
        </div>

        <!-- Needs a look first: how the loaded licences split by state. Each
             chip filters the list to that state; press again to clear. -->
        <div v-if="!failed && stateChips.length" class="flex flex-wrap gap-2" role="group" :aria-label="t('common.status')">
            <button v-for="c in stateChips" :key="c.key" type="button" class="chip" :class="['chip-' + (badge(c.key).replace('badge-', '')), { on: state === c.key }]"
                :aria-pressed="state === c.key" @click="toggleState(c.key)">
                <span class="chip-dot" aria-hidden="true" />
                {{ t('licence.state.' + c.key) }}
                <strong>{{ c.count }}</strong>
            </button>
        </div>

        <!-- Revocation is weak by design and the copy must not imply a kill
             switch: a licence verified entirely offline cannot be recalled. -->
        <div class="note">
            <Icon name="info" :size="18" class="note-ico" />
            <p class="text-sm" style="color:var(--body)">{{ t('licence.offline_notice') }}</p>
        </div>

        <div class="card p-4 grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 items-end">
            <label class="block min-w-0">
                <span class="label">{{ t('licence.restaurant') }}</span>
                <select v-model="restaurantId" class="input" @change="load">
                    <option value="">{{ t('licence.all_restaurants') }}</option>
                    <option v-for="r in restaurants" :key="r.id" :value="r.id">{{ r.name_en || r.name_ar || r.slug }}</option>
                </select>
            </label>
            <label class="block min-w-0">
                <span class="label">{{ t('common.status') }}</span>
                <select v-model="state" class="input">
                    <option value="">{{ t('licence.all_states') }}</option>
                    <option v-for="s in STATES" :key="s" :value="s">{{ t('licence.state.' + s) }}</option>
                </select>
            </label>
            <label class="block min-w-0">
                <span class="label">{{ t('licence.kind_label') }}</span>
                <select v-model="kind" class="input" @change="load">
                    <option value="">{{ t('licence.all_kinds') }}</option>
                    <option value="cloud">{{ t('licence.kind.cloud') }}</option>
                    <option value="offline">{{ t('licence.kind.offline') }}</option>
                </select>
            </label>
            <label class="block min-w-0">
                <span class="label">{{ t('licence.op_status_label') }}</span>
                <select v-model="opStatus" class="input" @change="load">
                    <option value="">{{ t('licence.all_op_statuses') }}</option>
                    <option v-for="s in ['active', 'suspended', 'expired']" :key="s" :value="s">{{ t('licence.op_status.' + s) }}</option>
                </select>
            </label>
            <label class="block min-w-0">
                <span class="label">{{ t('common.search') }}</span>
                <input v-model="search" class="input" :placeholder="t('licence.search_hint')" @change="load" />
            </label>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <!-- Phone: one card per licence, actions at full tap size -->
            <div class="md:hidden space-y-3">
                <div v-if="loading" class="card"><ListSkeleton :rows="4" /></div>
                <div v-else-if="!filtered.length" class="card p-6 text-center space-y-3">
                    <p class="text-sm" style="color:var(--body)">{{ t('licence.none') }}</p>
                    <RouterLink :to="{ name: 'admin.licences.new' }" class="btn btn-accent new-btn"><Icon name="plus" :size="16" />{{ t('licence.new_client') }}</RouterLink>
                </div>
                <article v-for="l in (loading ? [] : filtered)" :key="l.id" class="card lic-card" :class="'tone-' + toneOf(l)">
                    <div class="flex items-start justify-between gap-3">
                        <RouterLink :to="{ name: 'admin.licences.show', params: { id: l.id } }" class="min-w-0 flex-1">
                            <span class="mono lic-ref block truncate">{{ l.licence_ref }}</span>
                            <span class="block truncate text-sm" style="color:var(--body)">{{ clientName(l) }}</span>
                        </RouterLink>
                        <span v-if="isHeld(l) && !isRecord(l)" class="badge badge-red">{{ t('licence.op_status.' + l.status) }}</span>
                        <span v-else class="badge" :class="badge(l.state)">{{ t('licence.state.' + l.state) }}</span>
                    </div>
                    <dl class="lic-facts">
                        <div>
                            <dt>{{ t('licence.expires') }}</dt>
                            <dd :class="'exp-' + toneOf(l)">{{ expiryOf(l) }}</dd>
                        </div>
                        <div>
                            <dt>{{ t('licence.terminals') }}</dt>
                            <dd>{{ l.max_terminals }}</dd>
                        </div>
                        <div>
                            <dt>{{ t('licence.key_tail') }}</dt>
                            <dd class="mono" dir="ltr">…{{ l.key_last_four }}</dd>
                        </div>
                    </dl>
                    <div class="flex flex-wrap items-center gap-1.5">
                        <span class="badge" :class="l.kind === 'offline' ? 'badge-gray' : 'badge-green'">{{ t('licence.kind.' + l.kind) }}</span>
                        <span class="text-xs" style="color:var(--body)">{{ t('licence.enforcement.' + (l.enforcement || 'online')) }}</span>
                        <span v-for="m in l.modes" :key="m" class="lic-chip">{{ t('licence.mode.' + m) }}</span>
                    </div>
                    <div class="lic-actions">
                        <template v-if="!isRecord(l) && isOnline(l)">
                            <button v-if="isHeld(l)" class="btn btn-ghost" :disabled="acting === l.id" @click="quickResume(l)">{{ t('licence.resume') }}</button>
                            <button v-else-if="isLive(l)" class="btn btn-ghost act-amber" :disabled="acting === l.id" @click="quickSuspend(l)">{{ t('licence.suspend') }}</button>
                        </template>
                        <button v-if="isLive(l)" class="btn btn-ghost act-red" :disabled="acting === l.id" @click="quickRevoke(l)">{{ t('licence.revoke') }}</button>
                        <button v-else class="btn btn-ghost act-red" :disabled="acting === l.id" @click="quickDelete(l)">{{ t('licence.delete') }}</button>
                    </div>
                </article>
            </div>

            <!-- Tablet and up: the full table, scrolling inside its card if it must -->
            <div class="card overflow-x-auto hidden md:block">
                <table class="w-full text-sm lic-table" style="min-width:960px">
                    <thead>
                        <tr>
                            <th class="px-5 py-3 text-start">{{ t('licence.ref') }}</th>
                            <th class="px-3 py-3 text-start">{{ t('licence.restaurant') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('common.status') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('licence.expires') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('licence.kind_label') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('licence.terminals') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('licence.modes') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('licence.key_tail') }}</th>
                            <th class="px-3 py-3 text-center">{{ t('common.actions') }}</th>
                        </tr>
                    </thead>
                    <tbody>
                        <TableSkeleton v-if="loading" :cols="9" />
                        <tr v-else-if="!filtered.length">
                            <td colspan="9" class="px-5 py-10 text-center">
                                <p class="mb-3" style="color:var(--body)">{{ t('licence.none') }}</p>
                                <RouterLink :to="{ name: 'admin.licences.new' }" class="btn btn-accent new-btn"><Icon name="plus" :size="16" />{{ t('licence.new_client') }}</RouterLink>
                            </td>
                        </tr>
                        <tr v-for="l in filtered" :key="l.id" class="lic-row cursor-pointer" :class="'tone-' + toneOf(l)"
                            @click="router.push({ name: 'admin.licences.show', params: { id: l.id } })">
                            <td class="px-5 py-3 text-start">
                                <RouterLink :to="{ name: 'admin.licences.show', params: { id: l.id } }" class="mono lic-ref" @click.stop>{{ l.licence_ref }}</RouterLink>
                            </td>
                            <td class="px-3 py-3 text-start" style="color:var(--ink);max-width:240px">
                                <span class="block truncate">{{ clientName(l) }}</span>
                            </td>
                            <td class="px-3 py-3 text-center">
                                <!-- The dashboard status outranks the dates on the online
                                     path, so a held licence shows that, not "Active". -->
                                <span v-if="isHeld(l) && !isRecord(l)" class="badge badge-red">{{ t('licence.op_status.' + l.status) }}</span>
                                <span v-else class="badge" :class="badge(l.state)">{{ t('licence.state.' + l.state) }}</span>
                            </td>
                            <td class="px-3 py-3 text-center whitespace-nowrap" :class="'exp-' + toneOf(l)">{{ expiryOf(l) }}</td>
                            <td class="px-3 py-3 text-center">
                                <span class="badge" :class="l.kind === 'offline' ? 'badge-gray' : 'badge-green'">{{ t('licence.kind.' + l.kind) }}</span>
                                <div class="mt-1 text-xs" style="color:var(--body)">{{ t('licence.enforcement.' + (l.enforcement || 'online')) }}</div>
                            </td>
                            <td class="px-3 py-3 text-center"><span class="badge badge-gray">{{ l.max_terminals }}</span></td>
                            <td class="px-3 py-3">
                                <div class="flex flex-wrap justify-center gap-1">
                                    <span v-for="m in l.modes" :key="m" class="lic-chip">{{ t('licence.mode.' + m) }}</span>
                                </div>
                            </td>
                            <td class="px-3 py-3 text-center mono" dir="ltr" style="color:var(--body)">…{{ l.key_last_four }}</td>
                            <td class="px-3 py-3 text-center whitespace-nowrap" @click.stop>
                                <template v-if="!isRecord(l) && isOnline(l)">
                                    <button v-if="isHeld(l)" class="btn btn-ghost btn-sm"
                                        :disabled="acting === l.id" @click="quickResume(l)">{{ t('licence.resume') }}</button>
                                    <button v-else-if="isLive(l)" class="btn btn-ghost btn-sm act-amber"
                                        :disabled="acting === l.id" @click="quickSuspend(l)">{{ t('licence.suspend') }}</button>
                                </template>
                                <button v-if="isLive(l)" class="btn btn-ghost btn-sm act-red ms-1"
                                    :disabled="acting === l.id" @click="quickRevoke(l)">{{ t('licence.revoke') }}</button>
                                <button v-else class="btn btn-ghost btn-sm act-red ms-1"
                                    :disabled="acting === l.id" @click="quickDelete(l)">{{ t('licence.delete') }}</button>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </template>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale. */
.new-btn { min-height: 44px; }

/* Badge text on tinted fills: the theme's amber and gray text sit near 4:1 */
.badge-amber { color: var(--p-primary-800); }
.badge-gray { color: var(--body); }

.note { display: flex; align-items: flex-start; gap: 12px; padding: 14px 16px; border-radius: 12px;
    background: var(--amber-soft); border: 1px solid var(--line); }
.note-ico { color: var(--p-primary-800); flex: none; margin-top: 1px; }

/* State chips */
.chip { display: inline-flex; align-items: center; gap: 8px; min-height: 40px; padding: 0 14px; border-radius: 999px;
    background: var(--card); border: 1px solid var(--line); color: var(--ink); font-size: 14px; font-weight: 500; cursor: pointer;
    transition: border-color .15s, background .15s; }
.chip strong { font-family: var(--font-display); font-weight: 700; }
.chip:hover { border-color: var(--muted); }
.chip.on { border-color: var(--ink); background: var(--page); }
.chip-dot { width: 9px; height: 9px; border-radius: 50%; background: var(--gray); }
.chip-green .chip-dot { background: var(--green); }
.chip-amber .chip-dot { background: var(--accent); }
.chip-red .chip-dot { background: var(--red); }

/* Table */
.lic-table th { font-size: 12px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: var(--body);
    background: var(--page); white-space: nowrap; }
.lic-row { border-top: 1px solid var(--line); transition: background .15s; min-height: 56px; }
.lic-row:hover { background: var(--page); }
.lic-row > td:first-child { position: relative; }
.lic-row > td:first-child::before, .lic-card::before { content: ''; position: absolute; inset-block: 0; inset-inline-start: 0; width: 4px; background: transparent; }
.tone-green > td:first-child::before, .lic-card.tone-green::before { background: var(--green); }
.tone-amber > td:first-child::before, .lic-card.tone-amber::before { background: var(--accent); }
.tone-red > td:first-child::before, .lic-card.tone-red::before { background: var(--red); }
.tone-gray > td:first-child::before, .lic-card.tone-gray::before { background: var(--gray); }

.lic-ref { font-size: 14px; font-weight: 600; color: var(--ink); }
.lic-ref:hover { color: var(--p-primary-700); text-decoration: underline; }

/* Expiry text: colour repeats what the badge already says, never alone */
.exp-green, .exp-gray { color: var(--body); }
.exp-amber { color: var(--p-primary-800); font-weight: 600; }
.exp-red { color: var(--red); font-weight: 600; }

.act-amber { color: var(--p-primary-800); }
.act-red { color: var(--red); }

.lic-chip { font-size: 12px; font-weight: 600; padding: 2px 9px; border-radius: 999px; white-space: nowrap;
    background: var(--accent-soft); color: var(--p-primary-800); }

/* Phone card */
.lic-card { position: relative; overflow: hidden; padding: 16px 18px; padding-inline-start: 22px;
    display: flex; flex-direction: column; gap: 12px; }
.lic-facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin: 0; }
.lic-facts dt { font-size: 12px; color: var(--body); }
.lic-facts dd { margin: 2px 0 0; font-size: 14.5px; font-weight: 600; color: var(--ink); }
.lic-facts dd.exp-amber, .lic-facts dd.exp-red { font-weight: 700; }
.lic-facts dd.exp-amber { color: var(--p-primary-800); }
.lic-facts dd.exp-red { color: var(--red); }
.lic-actions { display: flex; flex-wrap: wrap; gap: 8px; padding-top: 12px; border-top: 1px solid var(--line); }
.lic-actions .btn { min-height: 44px; flex: 1 1 120px; justify-content: center; }
</style>
