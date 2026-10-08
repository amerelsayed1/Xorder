<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import TableSkeleton from '@xorder/ui/TableSkeleton.vue'
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
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.licences') }}</h1>
                <p class="page-sub">{{ t('licence.subtitle') }}</p>
            </div>
            <RouterLink :to="{ name: 'admin.licences.new' }" class="btn btn-accent">
                <Icon name="plus" :size="16" />{{ t('licence.new_client') }}
            </RouterLink>
        </div>

        <!-- Revocation is weak by design and the copy must not imply a kill
             switch: a licence verified entirely offline cannot be recalled. -->
        <div class="card p-4 flex items-start gap-3" style="border-inline-start:3px solid var(--amber)">
            <Icon name="info" :size="18" style="color:var(--amber);flex:none;margin-top:1px" />
            <p class="text-sm" style="color:var(--body)">{{ t('licence.offline_notice') }}</p>
        </div>

        <div class="card p-4 flex flex-wrap items-end gap-3">
            <label class="block" style="min-width:220px">
                <span class="label">{{ t('licence.restaurant') }}</span>
                <select v-model="restaurantId" class="input" @change="load">
                    <option value="">{{ t('licence.all_restaurants') }}</option>
                    <option v-for="r in restaurants" :key="r.id" :value="r.id">{{ r.name_en || r.name_ar || r.slug }}</option>
                </select>
            </label>
            <label class="block" style="min-width:180px">
                <span class="label">{{ t('common.status') }}</span>
                <select v-model="state" class="input">
                    <option value="">{{ t('licence.all_states') }}</option>
                    <option v-for="s in STATES" :key="s" :value="s">{{ t('licence.state.' + s) }}</option>
                </select>
            </label>
            <label class="block" style="min-width:160px">
                <span class="label">{{ t('licence.kind_label') }}</span>
                <select v-model="kind" class="input" @change="load">
                    <option value="">{{ t('licence.all_kinds') }}</option>
                    <option value="cloud">{{ t('licence.kind.cloud') }}</option>
                    <option value="offline">{{ t('licence.kind.offline') }}</option>
                </select>
            </label>
            <label class="block" style="min-width:180px">
                <span class="label">{{ t('licence.op_status_label') }}</span>
                <select v-model="opStatus" class="input" @change="load">
                    <option value="">{{ t('licence.all_op_statuses') }}</option>
                    <option v-for="s in ['active', 'suspended', 'expired']" :key="s" :value="s">{{ t('licence.op_status.' + s) }}</option>
                </select>
            </label>
            <label class="block" style="min-width:200px">
                <span class="label">{{ t('common.search') }}</span>
                <input v-model="search" class="input" :placeholder="t('licence.search_hint')" @change="load" />
            </label>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <div v-else class="card overflow-x-auto">
            <table class="w-full text-sm" style="min-width:960px">
                <thead>
                    <tr style="color:var(--muted)">
                        <th class="px-5 py-3 font-medium text-start" style="font-size:11px;letter-spacing:.06em;text-transform:uppercase">{{ t('licence.ref') }}</th>
                        <th class="px-3 py-3 font-medium text-start" style="font-size:11px;text-transform:uppercase">{{ t('licence.restaurant') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.kind_label') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.expires') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.terminals') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.modes') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('licence.key_tail') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('common.status') }}</th>
                        <th class="px-3 py-3 font-medium text-center" style="font-size:11px;text-transform:uppercase">{{ t('common.actions') }}</th>
                    </tr>
                </thead>
                <tbody>
                    <TableSkeleton v-if="loading" :cols="9" />
                    <tr v-else-if="!filtered.length">
                        <td colspan="9" class="px-5 py-8 text-center" style="color:var(--muted)">{{ t('licence.none') }}</td>
                    </tr>
                    <tr v-for="l in filtered" :key="l.id" class="border-t cursor-pointer hover:bg-black/[.015]"
                        :style="{ borderColor: 'var(--line)', opacity: ['revoked', 'superseded'].includes(l.state) ? 0.6 : 1 }"
                        @click="router.push({ name: 'admin.licences.show', params: { id: l.id } })">
                        <td class="px-5 py-3 text-start mono" style="color:var(--ink)">{{ l.licence_ref }}</td>
                        <td class="px-3 py-3 text-start" style="color:var(--body)">{{ clientName(l) }}</td>
                        <td class="px-3 py-3 text-center">
                            <span class="badge" :class="l.kind === 'offline' ? 'badge-gray' : 'badge-green'">{{ t('licence.kind.' + l.kind) }}</span>
                            <div class="mt-1" style="font-size:11px;color:var(--muted)">{{ t('licence.enforcement.' + (l.enforcement || 'online')) }}</div>
                        </td>
                        <td class="px-3 py-3 text-center" style="color:var(--body)">{{ expiryOf(l) }}</td>
                        <td class="px-3 py-3 text-center"><span class="badge badge-gray">{{ l.max_terminals }}</span></td>
                        <td class="px-3 py-3">
                            <div class="flex flex-wrap justify-center gap-1">
                                <span v-for="m in l.modes" :key="m" class="lic-chip">{{ t('licence.mode.' + m) }}</span>
                            </div>
                        </td>
                        <td class="px-3 py-3 text-center mono" style="color:var(--muted)">…{{ l.key_last_four }}</td>
                        <td class="px-3 py-3 text-center">
                            <!-- The dashboard status outranks the dates on the online
                                 path, so a held licence shows that, not "Active". -->
                            <span v-if="isHeld(l) && !isRecord(l)" class="badge badge-red">{{ t('licence.op_status.' + l.status) }}</span>
                            <span v-else class="badge" :class="badge(l.state)">{{ t('licence.state.' + l.state) }}</span>
                        </td>
                        <td class="px-3 py-3 text-center whitespace-nowrap" @click.stop>
                            <template v-if="!isRecord(l) && isOnline(l)">
                                <button v-if="isHeld(l)" class="btn btn-ghost btn-sm"
                                    :disabled="acting === l.id" @click="quickResume(l)">{{ t('licence.resume') }}</button>
                                <button v-else-if="isLive(l)" class="btn btn-ghost btn-sm" style="color:var(--amber)"
                                    :disabled="acting === l.id" @click="quickSuspend(l)">{{ t('licence.suspend') }}</button>
                            </template>
                            <button v-if="isLive(l)" class="btn btn-ghost btn-sm" style="color:var(--red)"
                                :disabled="acting === l.id" @click="quickRevoke(l)">{{ t('licence.revoke') }}</button>
                            <button v-else class="btn btn-ghost btn-sm" style="color:var(--red)"
                                :disabled="acting === l.id" @click="quickDelete(l)">{{ t('licence.delete') }}</button>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</template>

<style scoped>
.lic-chip {
    font-size: 11.5px;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--accent-soft, color-mix(in srgb, var(--accent) 10%, transparent));
    color: var(--accent-dark, var(--accent));
    white-space: nowrap;
}
</style>
