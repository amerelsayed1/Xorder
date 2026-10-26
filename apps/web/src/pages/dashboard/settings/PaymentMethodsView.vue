<script setup>
import { ref, computed, onMounted, onBeforeUnmount, reactive } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { useCaps } from '../../../lib/useCaps.js'
import Icon from '@xorder/ui/Icon.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'
import SettingsHeader from './SettingsHeader.vue'
import FinancialAccountsPanel from './FinancialAccountsPanel.vue'

const { t } = useI18n()
const { canUpdate } = useCaps('settings')

// Kinds map to a small palette so a scan of the list reads by category rather
// than only by name — cash rows glow warm, card rows sit blue, etc. Matches
// the design's per-tile colour classes.
const TENDER_KINDS = ['cash', 'card', 'external', 'other']
const KIND_STYLE = {
    cash: { bg: '#FFF1E2', color: '#B85E05' },
    card: { bg: '#EEF2FB', color: '#3656A8' },
    external: { bg: '#F1ECFA', color: '#6B45A8' },
    other: { bg: '#F4F1EC', color: '#4A443C' },
}

const tab = ref('methods')
// How many active accounts the Accounts tab holds; the panel reports it once
// it has loaded, so the tab can show a number before anyone opens it.
const accountCount = ref(null)
// The Accounts panel loads three lists, so it is mounted the first time the tab
// is opened rather than on every visit to Payment methods. It stays mounted
// afterwards (v-show) so switching back and forth does not refetch.
const accountsOpened = ref(false)
const rows = ref([])
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/tender-types'))
        rows.value = data.data
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const activeCount = computed(() => rows.value.filter(r => r.is_active).length)

// A short label the coloured tile shows — the first letter of the name in the
// row's active script, so Arabic names get an Arabic initial and English ones
// an English one. Falls back to the kind's initial for a nameless row.
function abbr(row) {
    const name = (row.name || '').trim()
    if (name) return [...name][0]
    return (row.kind || 'o')[0].toUpperCase()
}

// --- Inline expand + edit --------------------------------------------------
// Design pattern: clicking "Settings" opens a panel below the row with the
// method's editable fields; Save persists, Cancel discards.
const openId = ref(null)
const draft = reactive({ id: null, name: '', kind: 'cash', sort_order: 0 })
const savingId = ref(null)
const busyId = ref(null)

function openInline(row) {
    if (openId.value === row.id) { closeInline(); return }
    openId.value = row.id
    draft.id = row.id
    draft.name = row.name || ''
    draft.kind = row.kind || 'cash'
    draft.sort_order = row.sort_order ?? 0
}
function closeInline() {
    openId.value = null
    draft.id = null
    draft.name = ''
    draft.kind = 'cash'
    draft.sort_order = 0
}

// --- New-method modal ------------------------------------------------------
const showModal = ref(false)
const modalErrors = ref({})
const modalSaving = ref(false)
const modalForm = reactive({ name: '', kind: 'cash', is_active: true, sort_order: 0 })

function openCreate() {
    modalErrors.value = {}
    modalForm.name = ''
    modalForm.kind = 'cash'
    modalForm.is_active = true
    modalForm.sort_order = rows.value.length
    showModal.value = true
}
async function createMethod() {
    if (modalSaving.value) return
    if (!modalForm.name.trim()) {
        modalErrors.value = { name: [t('common.error')] }
        return
    }
    modalSaving.value = true
    try {
        await ensureCsrf()
        const { data } = await api.post('api/dashboard/tender-types', { ...modalForm, name: modalForm.name.trim() })
        rows.value.push(data.data)
        showModal.value = false
        showToast(t('pos_payment_methods.saved_toast', { name: data.data.name }))
    } catch (err) {
        modalErrors.value = err.response?.data?.errors || { name: [err.response?.data?.message || t('common.save_failed')] }
    } finally {
        modalSaving.value = false
    }
}

// --- Inline save -----------------------------------------------------------
async function saveInline() {
    if (savingId.value) return
    const row = rows.value.find(r => r.id === draft.id)
    if (!row) return closeInline()
    if (!draft.name.trim()) return
    savingId.value = row.id
    try {
        await ensureCsrf()
        const payload = { name: draft.name.trim(), kind: draft.kind, is_active: row.is_active, sort_order: Number(draft.sort_order) || 0 }
        const { data } = await api.put(`api/dashboard/tender-types/${row.id}`, payload)
        Object.assign(row, data.data)
        showToast(t('pos_payment_methods.saved_toast', { name: row.name }))
        // Row order can change when sort_order changes; resort locally so the
        // user sees the effect without a full reload.
        rows.value = [...rows.value].sort((a, b) => (a.sort_order - b.sort_order) || (a.id - b.id))
        closeInline()
    } catch (err) {
        alert(err.response?.data?.message || t('common.save_failed'))
    } finally {
        savingId.value = null
    }
}

// --- Toggle on/off ---------------------------------------------------------
async function toggle(row) {
    if (busyId.value) return
    // Guard: at least one method must stay enabled — every till needs
    // *something* to close a ticket on.
    if (row.is_active && activeCount.value === 1) {
        showToast(t('pos_payment_methods.need_one'), true)
        return
    }
    busyId.value = row.id
    const before = row.is_active
    row.is_active = !before
    try {
        await ensureCsrf()
        await api.put(`api/dashboard/tender-types/${row.id}`, {
            name: row.name, kind: row.kind, is_active: row.is_active, sort_order: row.sort_order ?? 0,
        })
        showToast(row.is_active
            ? t('pos_payment_methods.enabled_toast', { name: row.name })
            : t('pos_payment_methods.disabled_toast', { name: row.name }))
    } catch (err) {
        row.is_active = before
        alert(err.response?.data?.message || t('common.save_failed'))
    } finally {
        busyId.value = null
    }
}

// --- Deactivate (destroy is soft-delete on the server) --------------------
async function remove(row) {
    const ok = await confirm({
        title: t('pos_payment_methods.delete_confirm_title'),
        message: t('pos_payment_methods.delete_confirm_body', { name: row.name }),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/tender-types/${row.id}`)
        // Server soft-deletes (flips is_active). Reflect locally rather than
        // reload — the row stays in place so history stays traceable.
        row.is_active = false
        showToast(t('pos_payment_methods.deleted_toast', { name: row.name }))
    } catch (err) {
        alert(err.response?.data?.message || t('common.delete_failed'))
    }
}

// --- Toast -----------------------------------------------------------------
const toast = ref('')
const toastBad = ref(false)
let toastTimer = null
function showToast(message, bad = false) {
    toast.value = message
    toastBad.value = bad
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => { toast.value = '' }, 3200)
}
onBeforeUnmount(() => clearTimeout(toastTimer))

// --- Summary line under each method name ---------------------------------
// Design pattern: a one-liner that carries the "at a glance" state — the
// method's kind label, and (when off) a hint that it's disabled at the till.
function summary(row) {
    const kindLabel = t(`pos_money.tender_kind.${row.kind || 'other'}`)
    return kindLabel
}
</script>

<template>
    <div class="pm">
        <SettingsHeader
            :title="t('nav.pos_payment_methods')"
            :desc="t('pos_payment_methods.subtitle')"
        >
            <template v-if="canUpdate && tab === 'methods'" #actions>
                <button class="btn btn-accent" @click="openCreate">
                    <Icon name="plus" :size="16" />{{ t('pos_payment_methods.new_method') }}
                </button>
            </template>
        </SettingsHeader>

        <!-- Tab strip (methods / accounts). The Accounts tab (XORD-015) is its own
             panel, mounted the first time the tab is opened. -->
        <div class="pm-tabs" role="tablist">
            <button class="pm-tab" role="tab" :aria-selected="tab === 'methods'" :class="{ on: tab === 'methods' }" @click="tab = 'methods'">
                {{ t('pos_payment_methods.tab_methods') }}
                <span class="pm-tab-count mono">{{ t('pos_payment_methods.enabled_of', { on: activeCount, total: rows.length }) }}</span>
            </button>
            <button class="pm-tab" role="tab" :aria-selected="tab === 'accounts'" :class="{ on: tab === 'accounts' }" @click="tab = 'accounts'; accountsOpened = true">
                {{ t('pos_payment_methods.tab_accounts') }}
                <span class="pm-tab-count mono">{{ accountCount ?? '—' }}</span>
            </button>
        </div>

        <template v-if="tab === 'methods'">
            <ErrorState v-if="failed" @retry="load" />
            <div v-else-if="loading" class="card pm-skel" aria-hidden="true">
                <div v-for="n in 4" :key="n" class="set-skel" style="height: 56px"></div>
            </div>
            <template v-else>
                <div v-if="!rows.length" class="card set-empty">
                    <span class="set-empty-title">{{ t('pos_money.tenders_none') }}</span>
                    <span class="set-empty-hint">{{ t('pos_money.tenders_empty_hint') }}</span>
                    <button v-if="canUpdate" type="button" class="btn btn-accent" style="margin-top: 8px" @click="openCreate">
                        <Icon name="plus" :size="16" />{{ t('pos_payment_methods.new_method') }}
                    </button>
                </div>
                <div v-else class="card pm-list">
                    <div v-for="row in rows" :key="row.id" class="pm-row">
                        <!-- Header row: tile, name+summary, actions, toggle -->
                        <div class="pm-row-head">
                            <div class="pm-tile" :class="row.is_active ? 'k-' + (row.kind || 'other') : 'off'" aria-hidden="true">{{ abbr(row) }}</div>
                            <div class="pm-name-col">
                                <div class="pm-name" :class="{ dim: !row.is_active }">{{ row.name }}</div>
                                <div class="pm-summary">
                                    {{ summary(row) }}
                                    <span v-if="!row.is_active" class="set-chip"><span class="dot"></span>{{ t('common.inactive') }}</span>
                                </div>
                            </div>
                            <button v-if="canUpdate" class="pm-settings" :aria-expanded="openId === row.id" @click="openInline(row)">
                                {{ t('pos_payment_methods.method_settings') }}
                                <Icon name="chevronDown" :size="14" aria-hidden="true" :style="{ transform: openId === row.id ? 'rotate(180deg)' : 'none', transition: 'transform .15s' }" />
                            </button>
                            <!-- Row-level delete. The server soft-deletes (flips
                                 is_active) so past payments still resolve their
                                 tender FK — the confirm copy makes that clear. -->
                            <button
                                v-if="canUpdate && row.is_active"
                                type="button"
                                class="pm-icon-btn pm-icon-danger"
                                :title="t('common.delete')"
                                :aria-label="t('common.delete')"
                                @click="remove(row)"
                            ><Icon name="trash" :size="16" /></button>
                            <button
                                v-if="canUpdate"
                                type="button"
                                class="pm-toggle"
                                role="switch"
                                :aria-label="row.name"
                                :aria-checked="row.is_active"
                                :disabled="busyId === row.id"
                                @click="toggle(row)"
                            >
                                <span class="pm-track" :class="{ on: row.is_active }"><span class="pm-knob"></span></span>
                            </button>
                        </div>

                        <!-- Expand: editable fields (name / kind / sort_order) -->
                        <div v-if="openId === row.id" class="pm-body">
                            <div class="pm-fields">
                                <label class="pm-field">
                                    <span class="pm-label">{{ t('pos_payment_methods.method_name') }} <span class="pm-req">*</span></span>
                                    <input v-model="draft.name" class="input" maxlength="60" />
                                </label>
                                <label class="pm-field">
                                    <span class="pm-label">{{ t('pos_payment_methods.method_kind') }}</span>
                                    <div class="pm-seg">
                                        <button
                                            v-for="k in TENDER_KINDS"
                                            :key="k"
                                            type="button"
                                            class="pm-seg-btn"
                                            :class="{ on: draft.kind === k }"
                                            @click="draft.kind = k"
                                        >{{ t(`pos_money.tender_kind.${k}`) }}</button>
                                    </div>
                                </label>
                                <label class="pm-field pm-field-narrow">
                                    <span class="pm-label">{{ t('pos_payment_methods.method_sort') }}</span>
                                    <input v-model.number="draft.sort_order" type="number" min="0" class="input mono" />
                                    <span class="pm-hint">{{ t('pos_payment_methods.method_order_hint') }}</span>
                                </label>
                            </div>
                            <div class="pm-actions">
                                <button class="btn btn-accent" :disabled="savingId === row.id || !draft.name.trim()" @click="saveInline">
                                    {{ savingId === row.id ? t('common.saving') : t('pos_payment_methods.method_save') }}
                                </button>
                                <button class="btn btn-ghost" @click="closeInline">{{ t('pos_payment_methods.method_cancel') }}</button>
                                <span class="pm-spacer"></span>
                                <button v-if="canUpdate && row.is_active" class="pm-danger" @click="remove(row)">
                                    <Icon name="trash" :size="14" />{{ t('pos_money.deactivate') }}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
                <p v-if="rows.length" class="pm-footnote">{{ t('pos_payment_methods.active_hint') }}</p>
            </template>
        </template>

        <FinancialAccountsPanel v-if="accountsOpened" v-show="tab === 'accounts'" :methods="rows" @count="accountCount = $event" />

        <!-- Create modal: uses the same shell as other settings modals, styled
             to match the design's card. Edits go inline instead of here. -->
        <transition name="pm-modal">
            <div v-if="showModal" class="pm-modal-backdrop" @click.self="showModal = false">
                <div class="pm-modal" role="dialog" aria-modal="true" :aria-label="t('pos_payment_methods.new_method')">
                    <div class="pm-modal-head">{{ t('pos_payment_methods.new_method') }}</div>
                    <div class="pm-modal-body">
                        <label class="pm-field">
                            <span class="pm-label">{{ t('pos_payment_methods.method_name') }} <span class="pm-req">*</span></span>
                            <input v-model="modalForm.name" class="input" maxlength="60" :placeholder="t('pos_money.tender_name_placeholder')" />
                            <span v-if="modalErrors.name" class="pm-err">{{ Array.isArray(modalErrors.name) ? modalErrors.name[0] : modalErrors.name }}</span>
                        </label>
                        <label class="pm-field">
                            <span class="pm-label">{{ t('pos_payment_methods.method_kind') }}</span>
                            <div class="pm-seg">
                                <button
                                    v-for="k in TENDER_KINDS"
                                    :key="k"
                                    type="button"
                                    class="pm-seg-btn"
                                    :class="{ on: modalForm.kind === k }"
                                    @click="modalForm.kind = k"
                                >{{ t(`pos_money.tender_kind.${k}`) }}</button>
                            </div>
                        </label>
                    </div>
                    <div class="pm-modal-foot">
                        <button class="btn btn-accent" :disabled="modalSaving || !modalForm.name.trim()" @click="createMethod">
                            {{ modalSaving ? t('common.saving') : t('common.create') }}
                        </button>
                        <button class="btn btn-ghost" @click="showModal = false">{{ t('common.cancel') }}</button>
                    </div>
                </div>
            </div>
        </transition>

        <transition name="pm-toast">
            <div v-if="toast" class="pm-toast" role="status" aria-live="polite">
                <span class="pm-toast-dot" :class="{ bad: toastBad }"></span>
                <span>{{ toast }}</span>
            </div>
        </transition>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale. */
.pm { display: flex; flex-direction: column; gap: 18px; }
.mono { font-family: var(--font-mono); font-variant-numeric: tabular-nums; }

/* ── Tab strip ──────────────────────────────────────────────────── */
.pm-tabs {
    display: flex; gap: 4px; overflow-x: auto; scrollbar-width: none;
    box-shadow: inset 0 -1px 0 var(--line);
    margin-bottom: -4px;
}
.pm-tabs::-webkit-scrollbar { display: none; }
.pm-tab {
    flex: none; display: inline-flex; align-items: center; gap: 8px;
    min-height: 44px; padding: 10px 14px; background: transparent; border: 0;
    border-bottom: 2px solid transparent;
    font-family: inherit; font-size: 14.5px; font-weight: 500;
    color: var(--body); cursor: pointer; white-space: nowrap;
}
.pm-tab.on { border-bottom-color: var(--accent); color: var(--ink); font-weight: 700; }
.pm-tab:hover { color: var(--ink); }
.pm-tab:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; border-radius: 6px; }
.pm-tab-count {
    font-size: 12.5px; font-weight: 600; padding: 1px 8px;
    border-radius: 999px; background: var(--gray-soft); color: var(--body);
}

/* ── Method list ────────────────────────────────────────────────── */
.pm-list { overflow: hidden; }
.pm-skel { padding: 14px 18px; display: flex; flex-direction: column; gap: 10px; }
.pm-row { border-bottom: 1px solid var(--line); transition: background .15s; }
.pm-row:last-child { border-bottom: 0; }
.pm-row:hover { background: var(--page); }

.pm-row-head {
    display: flex; align-items: center; gap: 14px;
    padding: 12px 18px; flex-wrap: wrap; min-height: 68px;
}
/* Category tile: the letter reads by kind at a glance. Kind is also written
   out in the summary line, so colour is never the only cue. */
.pm-tile {
    flex: none; width: 40px; height: 40px; border-radius: 10px;
    display: grid; place-items: center;
    font-size: 14px; font-weight: 700;
}
.pm-tile.k-cash { background: var(--green-soft); color: var(--green); }
.pm-tile.k-card { background: var(--accent-soft); color: var(--p-primary-800); }
.pm-tile.k-external { background: var(--ink); color: var(--card); }
.pm-tile.k-other, .pm-tile.off { background: var(--gray-soft); color: var(--body); }
.pm-name-col { flex: 1 1 180px; min-width: 0; }
.pm-name { font-size: 15.5px; font-weight: 600; color: var(--ink); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pm-name.dim { color: var(--body); }
.pm-summary { margin-top: 3px; font-size: 13px; color: var(--body); display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }

.pm-settings {
    white-space: nowrap; min-height: 40px; padding: 0 12px;
    border: 0; border-radius: 8px; background: transparent;
    display: inline-flex; align-items: center; gap: 6px;
    font-family: inherit; font-size: 14px; font-weight: 500; color: var(--body);
    cursor: pointer; transition: background .15s;
}
.pm-settings:hover { background: var(--gray-soft); color: var(--ink); }
.pm-settings:focus-visible, .pm-icon-btn:focus-visible, .pm-toggle:focus-visible, .pm-danger:focus-visible,
.pm-seg-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }

.pm-icon-btn {
    display: grid; place-items: center;
    width: 40px; height: 40px; flex: none;
    border: 0; border-radius: 8px; background: transparent;
    color: var(--body); cursor: pointer; transition: background .15s, color .15s;
}
.pm-icon-btn:hover { background: var(--gray-soft); color: var(--ink); }
.pm-icon-danger:hover { background: var(--red-soft); color: var(--red); }

.pm-toggle {
    display: inline-flex; align-items: center; justify-content: center;
    min-width: 44px; min-height: 44px;
    border: 0; background: transparent; padding: 0;
    cursor: pointer; flex: none;
}
.pm-toggle:disabled { cursor: default; opacity: .6; }
.pm-track {
    position: relative; width: 40px; height: 23px; border-radius: 999px;
    background: var(--muted); transition: background .15s; flex: none;
}
.pm-track.on { background: var(--green); }
/* Logical offset so the knob sits on the start side when off and the end side
   when on, in both writing directions. */
.pm-knob {
    position: absolute; top: 2px; inset-inline-start: 2px;
    width: 19px; height: 19px; border-radius: 50%; background: #fff;
    box-shadow: 0 1px 2px rgba(0, 0, 0, .25);
    transition: inset-inline-start .15s;
}
.pm-track.on .pm-knob { inset-inline-start: 19px; }

/* ── Inline expand body ────────────────────────────────────────── */
.pm-body {
    padding: 16px 18px 18px;
    /* Align the body with the name column, not the tile. */
    margin-inline-start: 54px;
    display: flex; flex-direction: column; gap: 16px;
    background: var(--page);
    border-top: 1px solid var(--line);
}
.pm-fields { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr)); gap: 16px; }
.pm-field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.pm-field-narrow { max-width: 240px; }
.pm-label { font-size: 13.5px; font-weight: 600; color: var(--body); }
.pm-req { color: var(--red); }
.pm-hint { font-size: 13px; color: var(--body); }
.pm-err { font-size: 13px; color: var(--red); }

.pm-seg {
    display: flex; background: var(--gray-soft); border-radius: 10px;
    padding: 3px; gap: 2px; overflow-x: auto;
}
.pm-seg-btn {
    flex: 1; white-space: nowrap; min-height: 40px; padding: 0 12px;
    border: 0; border-radius: 8px; background: transparent;
    font-family: inherit; font-size: 13.5px; font-weight: 500;
    color: var(--body); cursor: pointer;
    transition: background .15s, color .15s, box-shadow .15s;
}
.pm-seg-btn.on { background: var(--card); color: var(--ink); font-weight: 700; box-shadow: 0 1px 2px rgba(0, 0, 0, .08); }

.pm-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding-top: 14px; border-top: 1px solid var(--line); }
.pm-spacer { flex: 1; }
.pm-danger {
    display: inline-flex; align-items: center; gap: 6px;
    min-height: 40px; padding: 0 12px; border: 0; border-radius: 8px;
    background: transparent; color: var(--red);
    font-family: inherit; font-size: 14px; font-weight: 500; cursor: pointer;
}
.pm-danger:hover { background: var(--red-soft); }

.pm-footnote { font-size: 13px; line-height: 1.6; color: var(--body); margin: 0; }

/* ── Create modal ──────────────────────────────────────────────── */
.pm-modal-backdrop {
    position: fixed; inset: 0; background: rgba(31, 27, 22, .4);
    z-index: 20; display: flex; align-items: center; justify-content: center;
    padding: 16px;
}
.pm-modal {
    width: 100%; max-width: 460px; max-height: 90vh; display: flex; flex-direction: column;
    background: var(--card); border: 1px solid var(--line);
    border-radius: 15px; box-shadow: 0 20px 50px rgba(31, 27, 22, .25);
    overflow: hidden;
}
.pm-modal-head {
    padding: 18px 20px; border-bottom: 1px solid var(--line);
    font-size: 17px; font-weight: 700; color: var(--ink);
}
.pm-modal-body { padding: 20px; display: flex; flex-direction: column; gap: 16px; overflow-y: auto; }
.pm-modal-foot {
    display: flex; flex-wrap: wrap; gap: 8px; padding: 14px 20px;
    border-top: 1px solid var(--line); background: var(--page);
}
.pm-modal-enter-from, .pm-modal-leave-to { opacity: 0; }
.pm-modal-enter-active, .pm-modal-leave-active { transition: opacity .15s; }

/* ── Toast ─────────────────────────────────────────────────────── */
/* Centred with logical insets + auto margins so it is correct in RTL too. */
.pm-toast {
    position: fixed; bottom: 24px; inset-inline: 0; margin-inline: auto; width: max-content; max-width: calc(100% - 32px);
    z-index: 15; display: flex; align-items: center; gap: 10px;
    padding: 12px 16px; background: var(--ink); color: #fff;
    border-radius: 12px; box-shadow: 0 10px 30px rgba(31, 27, 22, .25);
    font-size: 14px;
}
.pm-toast-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green-soft); flex: none; }
.pm-toast-dot.bad { background: var(--red-soft); }
.pm-toast-enter-from, .pm-toast-leave-to { opacity: 0; transform: translateY(10px); }
.pm-toast-enter-active, .pm-toast-leave-active { transition: opacity .18s, transform .18s; }

/* ── Phone ─────────────────────────────────────────────────────── */
@media (max-width: 640px) {
    /* tile + name + switch on the first line; "Settings" and delete beneath. */
    .pm-row-head {
        display: grid; grid-template-columns: 40px minmax(0, 1fr) auto; gap: 4px 12px;
        grid-template-areas: "tile name toggle" ". set del";
        padding-inline: 14px; align-items: center;
    }
    .pm-tile { grid-area: tile; }
    .pm-name-col { grid-area: name; }
    .pm-toggle { grid-area: toggle; }
    .pm-settings { grid-area: set; justify-self: start; min-height: 44px; margin-inline-start: -12px; }
    .pm-icon-btn { grid-area: del; justify-self: end; width: 44px; height: 44px; }
    .pm-body { margin-inline-start: 0; padding-inline: 14px; }
    .pm-seg-btn, .pm-danger { min-height: 44px; }
    .pm-actions .btn { flex: 1 1 auto; min-height: 44px; }
    .pm-modal-foot .btn { flex: 1 1 auto; min-height: 44px; }
    .pm-skel { padding-inline: 14px; }
}
</style>
