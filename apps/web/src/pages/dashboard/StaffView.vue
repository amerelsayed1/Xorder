<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { useCaps } from '../../lib/useCaps.js'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import Icon from '@xorder/ui/Icon.vue'
import Modal from '@xorder/ui/Modal.vue'
import FormError from '@xorder/ui/FormError.vue'
import SettingsHeader from './settings/SettingsHeader.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import { pickLocalized } from '@xorder/ui/localize.js'

const { t, locale } = useI18n()
const auth = useAuth()
// Per-action gates so the UI offers only what the API would accept.
const { canCreate, canUpdate, canDelete } = useCaps('staff')
const rows = ref([])
const loading = ref(true)
const busy = ref(null)

async function load() {
    loading.value = true
    try {
        const { data } = await api.get('api/dashboard/staff')
        rows.value = data.data
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Roles are named per restaurant in both languages; fall back to the English
// name when a tenant left the Arabic one blank.
// The owner's access is implicit — no Role governs them — so the column says
// what is true rather than borrowing a role name that would not apply.
const roleLabel = (u) => u.is_owner
    ? t('team.owner_full_access')
    : (pickLocalized({ name_en: u.role_name, name_ar: u.role_name_ar }, 'name', locale.value) || u.role_name || '—')

// Avatar initials. Latin names give their first two letters; Arabic (and any
// other script without a case distinction) gives the first letter of the first
// two words, which is what actually reads as a monogram in Arabic.
function initials(name) {
    const clean = String(name || '').trim()
    if (!clean) return '—'
    if (/^[\u0000-\u024F\s.'-]+$/.test(clean)) return clean.replace(/\s+/g, '').slice(0, 2).toUpperCase()
    const words = clean.split(/\s+/)
    return words.slice(0, 2).map((w) => w[0]).join('')
}

// One row, one primary action. Reset-password and delete are real but rare, so
// they sit behind the row's ⋯ toggle instead of turning every row into a
// four-button toolbar. Only one row's menu is open at a time.
const openMenu = ref(null)
const hasMenu = (u) => !u.is_owner && (canUpdate.value || canDelete.value)
const toggleMenu = (u) => { openMenu.value = openMenu.value === u.id ? null : u.id }

async function resetPassword(u) {
    const ok = await confirm({
        title: t('team.reset_password_title', { name: u.name }),
        message: t('team.reset_password_message'),
        confirmText: t('team.reset_password_confirm'),
        cancelText: t('common.cancel'),
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        const { data } = await api.post(`api/dashboard/staff/${u.id}/reset-password`)
        await alert({
            title: t('common.success'),
            message: t('team.new_password', { password: data.generated_password }),
            variant: 'success',
        })
    } catch (err) {
        alert(err.response?.data?.message || t('team.action_failed'))
    } finally {
        busy.value = null
    }
}

// ------------------------------------------------------------- POS PIN
// POS-BE-024. The till-unlock PIN is a separate credential from the dashboard
// password on purpose: a stolen till must not become dashboard access. So this
// sets and clears it, and never reads it — the server keeps only a PBKDF2
// verifier and no endpoint will ever hand the digits back.
//
// Client-side mirror of PosPinController::guard():
//   • self, always (a cashier may set their own PIN without staff.update)
//   • anyone else, only with staff.update
//   • the OWNER's PIN, only by the owner (the guard 404s everyone else)
// Plus feature:pos, which the whole route group sits behind, and the
// subscription.writable stack that every write here carries.
const isSelf = (u) => u.id === auth.user?.id
const canSetPin = (u) => auth.hasFeature('pos')
    && !auth.isReadOnly
    && (isSelf(u) || (canUpdate.value && !u.is_owner))

// UserResource does not serialise whether a PIN exists, so the list cannot
// know the state on load — the endpoints answer `pin_set`, but only to the
// request that just changed it. We record what we have been told this session
// and show nothing where we genuinely do not know, rather than guessing.
const pinState = reactive({})

const pinModal = ref(null) // the staff row being edited
const pinValue = ref('')
const pinConfirm = ref('')
const pinErrors = ref({})
const pinSaving = ref(false)

const pinMismatch = computed(() => pinConfirm.value.length > 0 && pinValue.value !== pinConfirm.value)
// Exactly four digits: the till's keypad submits on the fourth, so a longer
// PIN could never be typed there (S2-2, 16 Oct 2026). The API enforces the same.
const pinValid = computed(() => /^[0-9]{4}$/.test(pinValue.value) && pinValue.value === pinConfirm.value)

function openPin(u) {
    pinModal.value = u
    pinValue.value = ''
    pinConfirm.value = ''
    pinErrors.value = {}
}

function closePin() {
    // Never leave the plaintext sitting in memory behind a closed sheet.
    pinValue.value = ''
    pinConfirm.value = ''
    pinModal.value = null
}

async function savePin() {
    if (pinSaving.value || !pinValid.value) return
    pinErrors.value = {}
    pinSaving.value = true
    const target = pinModal.value
    try {
        const { data } = await api.put(`api/dashboard/staff/${target.id}/pin`, { pin: pinValue.value })
        // Only the resulting state is kept — the digits are dropped here and
        // are not echoed anywhere in the UI.
        pinState[target.id] = data?.pin_set !== false
        closePin()
        alert({
            title: t('common.success'),
            message: t('pos_pin.set_done', { name: target.name }),
            variant: 'success',
        })
    } catch (err) {
        pinErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(pinErrors.value).length) alert(err.response?.data?.message || t('team.action_failed'))
    } finally {
        pinSaving.value = false
    }
}

async function clearPin(u) {
    const ok = await confirm({
        title: t('pos_pin.clear_title', { name: u.name }),
        message: t('pos_pin.clear_message'),
        confirmText: t('pos_pin.clear'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        const { data } = await api.delete(`api/dashboard/staff/${u.id}/pin`)
        pinState[u.id] = data?.pin_set === true
        if (pinModal.value?.id === u.id) closePin()
    } catch (err) {
        alert(err.response?.data?.message || t('team.action_failed'))
    }
}

async function remove(u) {
    const ok = await confirm({
        title: t('team.delete_title', { name: u.name }),
        message: t('team.delete_message'),
        confirmText: t('team.delete_confirm'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    busy.value = u.id
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/staff/${u.id}`)
        await load()
    } catch (err) {
        alert(err.response?.data?.message || t('team.action_failed'))
    } finally {
        busy.value = null
    }
}
</script>

<template>
    <SettingsHeader class="staff-head" :title="t('team.staff_title')" :desc="t('team.staff_sub')">
        <template #actions>
            <RouterLink v-if="canCreate" :to="{ name: 'dashboard.staff.create' }" class="set-btn-primary act">
                <Icon name="plus" :size="15" />{{ t('team.add_staff') }}
            </RouterLink>
        </template>
    </SettingsHeader>

    <!-- Skeleton keeps the row height so the page does not jump on load. -->
    <div v-if="loading" class="card">
        <div v-for="n in 3" :key="n" class="skel-row">
            <div class="set-skel" style="width:44px;height:44px;border-radius:13px;flex:none"></div>
            <div style="flex:1;display:flex;flex-direction:column;gap:8px">
                <div class="set-skel" style="height:14px;width:38%;border-radius:6px"></div>
                <div class="set-skel" style="height:11px;width:22%;border-radius:6px"></div>
            </div>
            <div class="set-skel" style="height:26px;width:72px;border-radius:999px"></div>
        </div>
    </div>

    <div v-else-if="!rows.length" class="card empty">
        <span class="empty-ico" aria-hidden="true"><i class="pi pi-users" style="font-size:22px" aria-hidden="true"></i></span>
        <p class="empty-text">{{ t('team.staff_empty') }}</p>
        <RouterLink v-if="canCreate" :to="{ name: 'dashboard.staff.create' }" class="set-btn-primary act">
            <Icon name="plus" :size="15" />{{ t('team.add_staff') }}
        </RouterLink>
    </div>

    <ul v-else class="card list">
        <li v-for="u in rows" :key="u.id" class="row">
            <div class="row-top">
                <div class="avatar-tile" :class="{ 'avatar-owner': u.is_owner }" aria-hidden="true">{{ initials(u.name) }}</div>

                <div class="row-id">
                    <div class="row-name">
                        <strong class="truncate">{{ u.name }}</strong>
                        <span class="chip" :class="u.is_owner ? 'chip-owner' : 'chip-role'">{{ roleLabel(u) }}</span>
                    </div>
                    <span class="row-sub" dir="ltr">@{{ u.username }}</span>
                </div>

                <div class="row-status">
                    <span class="chip" :class="u.status === 'ACTIVE' ? 'chip-green' : (u.status === 'SUSPENDED' ? 'chip-red' : 'chip-gray')">
                        <span class="dot"></span>{{ t(`status.${u.status}`) }}
                    </span>
                    <!-- Only rendered once this session has actually been told the
                         answer: the PIN is write-only and no read endpoint reports
                         whether one exists, so an unconditional chip would be a guess. -->
                    <span v-if="pinState[u.id] !== undefined" class="note">
                        {{ pinState[u.id] ? t('pos_pin.state_set') : t('pos_pin.state_none') }}
                    </span>
                </div>
            </div>

            <div class="row-actions">
                <button v-if="canSetPin(u)" type="button" class="set-btn act" :title="t('pos_pin.explainer')" @click="openPin(u)">
                    {{ t('pos_pin.action') }}
                    <i class="pi pi-info-circle" style="font-size: 12px" aria-hidden="true"></i>
                </button>
                <!-- The owner is listed, never actioned: the API 404s on every
                     write against that account, so offering the controls here
                     would only produce dead buttons. -->
                <span v-if="u.is_owner" class="note">{{ t('team.owner_not_editable') }}</span>
                <RouterLink v-else-if="canUpdate" :to="{ name: 'dashboard.staff.edit', params: { id: u.id } }" class="set-btn act">{{ t('common.edit') }}</RouterLink>
                <button v-if="hasMenu(u)" type="button" class="set-btn set-btn-icon act-icon"
                    :title="t('common.more')" :aria-label="t('common.more')"
                    :aria-expanded="openMenu === u.id" @click="toggleMenu(u)">⋯</button>
            </div>

            <div v-if="openMenu === u.id" class="row-more">
                <button v-if="canUpdate" type="button" class="set-btn act" :disabled="busy === u.id" @click="resetPassword(u)">{{ t('team.reset_password') }}</button>
                <button v-if="canDelete" type="button" class="set-btn set-btn-danger act" :disabled="busy === u.id" @click="remove(u)">{{ t('team.delete_staff') }}</button>
            </div>
        </li>
    </ul>

    <!--
        Set / reset a till PIN. Write-only in both directions: the field is
        never prefilled (nothing to prefill it from), the value is dropped
        the moment the request returns, and the success notice reports the
        state, never the digits.
    -->
    <Modal v-if="pinModal" :title="t('pos_pin.title')" :subtitle="t('pos_pin.subtitle', { name: pinModal.name })" @close="closePin">
        <form @submit.prevent="savePin" class="space-y-4">
            <p class="text-sm" style="color:var(--body)">{{ t('pos_pin.explainer') }}</p>
            <p class="text-sm" style="color:var(--body)">{{ t('pos_pin.state_unknown') }}</p>

            <label class="block">
                <span class="label">{{ t('pos_pin.new_pin') }}</span>
                <input v-model="pinValue" type="password" class="input mono" dir="ltr" inputmode="numeric"
                    autocomplete="new-password" maxlength="4" data-en-digits placeholder="••••" />
                <p class="text-sm mt-1" style="color:var(--body)">{{ t('pos_pin.rule') }}</p>
                <FormError :errors="pinErrors" field="pin" />
            </label>

            <label class="block">
                <span class="label">{{ t('pos_pin.confirm_pin') }}</span>
                <input v-model="pinConfirm" type="password" class="input mono" dir="ltr" inputmode="numeric"
                    autocomplete="new-password" maxlength="4" data-en-digits placeholder="••••" />
                <p v-if="pinMismatch" class="text-sm mt-1" style="color:var(--red)">{{ t('pos_pin.mismatch') }}</p>
            </label>

            <p class="rounded-lg p-3 text-sm" style="background:var(--amber-soft);color:var(--p-primary-800)">{{ t('pos_pin.once_note') }}</p>

            <div class="flex flex-wrap items-center gap-3 pt-1">
                <button type="submit" class="btn btn-accent act" :disabled="pinSaving || !pinValid">{{ pinSaving ? t('common.saving') : t('pos_pin.save') }}</button>
                <button type="button" class="btn btn-ghost act" @click="closePin">{{ t('common.cancel') }}</button>
                <button type="button" class="btn btn-ghost act" style="color:var(--red);margin-inline-start:auto" @click="clearPin(pinModal)">{{ t('pos_pin.clear') }}</button>
            </div>
        </form>
    </Modal>
</template>

<style scoped>
/* Colours come from the shared theme variables only. The settings shell's
   own text is nudged to --body so secondary copy stays readable. */
.staff-head :deep(.set-desc), .staff-head :deep(.set-crumb) { color: var(--body); font-size: 14px; }

.list { list-style: none; margin: 0; padding: 0; overflow: hidden; }
.row { display: flex; flex-wrap: wrap; align-items: center; gap: 10px 16px; padding: 14px 20px; min-height: 72px;
    border-top: 1px solid var(--line); transition: background .15s; }
.row:first-child { border-top: 0; }
.row:hover { background: var(--page); }
.row-top { display: flex; align-items: center; gap: 14px; flex: 1 1 320px; min-width: 0; flex-wrap: wrap; }
.row-id { flex: 1 1 160px; min-width: 0; display: flex; flex-direction: column; align-items: flex-start; gap: 3px; }
.row-name { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; min-width: 0; max-width: 100%; }
.row-name strong { font-size: 15.5px; font-weight: 700; color: var(--ink); min-width: 0; }
.row-sub { font-family: var(--font-mono); font-size: 13px; color: var(--body); }
.row-status { display: flex; flex-direction: column; align-items: flex-start; gap: 4px; min-width: 96px; }
.row-actions { display: flex; align-items: center; gap: 8px; margin-inline-start: auto; flex-wrap: wrap; }
.row-more { width: 100%; display: flex; flex-wrap: wrap; gap: 8px; padding-top: 12px; border-top: 1px solid var(--line); }
.note { font-size: 13px; color: var(--body); }

.avatar-tile { width: 44px; height: 44px; flex: none; border-radius: 13px; display: grid; place-items: center;
    font-size: 14.5px; font-weight: 700; background: var(--accent-soft); color: var(--p-primary-800); }
.avatar-owner { background: var(--ink); color: var(--card); }

.chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px; border-radius: 999px; font-size: 12.5px; font-weight: 600;
    background: var(--gray-soft); color: var(--body); }
.chip .dot { width: 6px; height: 6px; border-radius: 999px; background: currentColor; }
.chip-role { background: var(--accent-soft); color: var(--p-primary-800); }
.chip-owner { background: var(--ink); color: var(--card); }
.chip-green { background: var(--green-soft); color: var(--green); }
.chip-red { background: var(--red-soft); color: var(--red); }
.chip-gray { background: var(--gray-soft); color: var(--body); }

.act { min-height: 40px; font-size: 14px; justify-content: center; }
.act-icon { width: 40px; height: 40px; }

.skel-row { display: flex; align-items: center; gap: 14px; padding: 14px 20px; border-top: 1px solid var(--line); }
.skel-row:first-child { border-top: 0; }

.empty { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 40px 20px; text-align: center; }
.empty-ico { width: 48px; height: 48px; border-radius: 14px; display: grid; place-items: center;
    background: var(--accent-soft); color: var(--p-primary-700); }
.empty-text { font-size: 15.5px; font-weight: 600; color: var(--ink); max-width: 420px; }

@media (max-width: 640px) {
    .row { padding-inline: 14px; }
    .row-actions { width: 100%; justify-content: flex-end; }
    .act { min-height: 44px; }
    .act-icon { width: 44px; height: 44px; }
}
</style>
