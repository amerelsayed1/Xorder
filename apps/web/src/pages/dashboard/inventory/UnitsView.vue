<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

// CB-09 slice a. Units are what purchases and stock are measured in. The
// server creates the seven defaults (ea, kg, g, l, ml, box, pack) on the
// first read, so a new client never sees an empty list. A unit's code is
// immutable and there is no delete; a unit is retired instead.
// purchase.manage opens the page and gates writes (see SuppliersView).
const { t, locale } = useI18n()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)

const rows = ref([])
const loading = ref(true)
const failed = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/units'))
        rows.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Units carry both names by default (seeded from the till's list), so show
// the one matching the UI language regardless of the menu's content languages.
const nameOf = (u) => pickLocalized(u, 'name', locale.value) || u.name_en || u.name_ar || u.code

// ------------------------------------------------------------------ editor
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const saving = ref(false)
const blank = () => ({ code: '', name_en: '', name_ar: '', eta_unit_type: '', allows_fraction: false, sort_order: 0, is_active: true })
const form = reactive(blank())

function openCreate() {
    editing.value = null
    errors.value = {}
    const next = rows.value.reduce((m, u) => Math.max(m, u.sort_order || 0), 0) + 10
    Object.assign(form, blank(), { sort_order: next })
    showModal.value = true
}
function openEdit(u) {
    editing.value = u
    errors.value = {}
    Object.assign(form, blank(), {
        code: u.code, name_en: u.name_en || '', name_ar: u.name_ar || '',
        eta_unit_type: u.eta_unit_type || '', allows_fraction: !!u.allows_fraction,
        sort_order: u.sort_order ?? 0, is_active: !!u.is_active,
    })
    showModal.value = true
}

// Never sends `code` on update: the server ignores it anyway, and leaving it
// out says so.
function payload(src, { withCode }) {
    const out = {
        name_en: src.name_en, name_ar: src.name_ar,
        eta_unit_type: src.eta_unit_type,
        allows_fraction: !!src.allows_fraction,
        sort_order: Number(src.sort_order) || 0,
        is_active: !!src.is_active,
    }
    if (withCode) out.code = src.code
    return out
}

function replaceRow(row) {
    const i = rows.value.findIndex((x) => x.id === row.id)
    if (i === -1) rows.value.push(row)
    else rows.value.splice(i, 1, row)
    rows.value.sort((a, b) => (a.sort_order - b.sort_order) || (a.id - b.id))
}

async function save() {
    if (saving.value) return
    saving.value = true
    errors.value = {}
    try {
        const { data } = editing.value
            ? await api.put(`api/dashboard/units/${editing.value.id}`, payload(form, { withCode: false }))
            : await api.post('api/dashboard/units', payload(form, { withCode: true }))
        replaceRow(data.data)
        showModal.value = false
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

async function setActive(u, active) {
    if (!active) {
        const ok = await confirm({
            title: t('purchasing.retire_unit_title'),
            message: t('purchasing.retire_unit_message', { name: nameOf(u) }),
            confirmText: t('purchasing.retire'),
            cancelText: t('common.cancel'),
        })
        if (!ok) return
    }
    try {
        const { data } = await api.put(`api/dashboard/units/${u.id}`, payload({ ...u, is_active: active }, { withCode: false }))
        replaceRow(data.data)
    } catch (err) {
        alert(err.response?.data?.message || t('common.error'))
    }
}
</script>

<template>
    <div class="space-y-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('purchasing.units_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.units_sub') }}</p>
            </div>
            <button v-if="canWrite" type="button" class="btn btn-accent" @click="openCreate">
                <Icon name="plus" :size="16" />{{ t('purchasing.add_unit') }}
            </button>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <div class="card overflow-hidden">
                <ListSkeleton v-if="loading" />
                <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('purchasing.none_units') }}</div>
                <ul v-else>
                    <li v-for="u in rows" :key="u.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)" :style="u.is_active ? '' : 'opacity:.65'">
                        <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0 mono text-sm" dir="ltr" style="background:var(--accent-soft);color:var(--accent)">{{ u.code }}</div>
                        <div class="flex-1 min-w-0">
                            <div class="font-medium" style="color:var(--ink)">{{ nameOf(u) }}</div>
                            <div class="text-xs flex flex-wrap items-center gap-2" style="color:var(--muted)">
                                <span class="mono" dir="ltr">{{ u.eta_unit_type }}</span>
                                <span>·</span>
                                <span>{{ u.allows_fraction ? t('purchasing.fractions') : t('purchasing.whole_only') }}</span>
                            </div>
                        </div>
                        <StatusBadge :value="u.is_active" :label="u.is_active ? t('common.active') : t('purchasing.retired')" />
                        <button v-if="canWrite" type="button" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')" @click="openEdit(u)"><Icon name="edit" :size="17" /></button>
                        <button v-if="canWrite && u.is_active" type="button" class="btn btn-ghost btn-sm" @click="setActive(u, false)">{{ t('purchasing.retire') }}</button>
                        <button v-else-if="canWrite" type="button" class="btn btn-ghost btn-sm" @click="setActive(u, true)">{{ t('purchasing.reactivate') }}</button>
                    </li>
                </ul>
            </div>
            <p v-if="!loading && rows.length" class="text-xs" style="color:var(--muted)">{{ t('purchasing.never_deleted') }}</p>
        </template>

        <Dialog v-if="showModal" :title="editing ? t('purchasing.edit_unit') : t('purchasing.add_unit')" @close="showModal = false">
            <form class="space-y-4" @submit.prevent="save">
                <label class="block"><span class="label">{{ t('purchasing.unit_code') }}</span>
                    <input v-model="form.code" class="input mono" dir="ltr" maxlength="16" :disabled="!!editing" autocapitalize="off" spellcheck="false" />
                    <span class="text-xs" style="color:var(--muted)">{{ editing ? t('purchasing.unit_code_locked') : t('purchasing.unit_code_hint') }}</span>
                    <FormError :errors="errors" field="code" /></label>
                <!-- Both names, always: unit names are short, and the
                     seeded defaults already carry both languages. -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block" dir="ltr"><span class="label">{{ t('common.name_en') }}</span>
                        <input v-model="form.name_en" class="input" maxlength="120" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" maxlength="120" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.eta_type') }}</span>
                        <input v-model="form.eta_unit_type" class="input mono" dir="ltr" maxlength="6" placeholder="EA" autocapitalize="characters" spellcheck="false" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.eta_type_hint') }}</span>
                        <FormError :errors="errors" field="eta_unit_type" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.sort_order') }}</span>
                        <input v-model.number="form.sort_order" type="number" min="0" step="1" class="input" dir="ltr" />
                        <FormError :errors="errors" field="sort_order" /></label>
                </div>
                <div class="block">
                    <label class="flex items-center gap-2 text-sm" style="color:var(--body)">
                        <button type="button" class="switch" :class="{ on: form.allows_fraction }" :aria-pressed="form.allows_fraction" @click="form.allows_fraction = !form.allows_fraction"></button>
                        {{ t('purchasing.allows_fraction') }}
                    </label>
                    <p class="text-xs mt-1" style="color:var(--muted)">{{ t('purchasing.allows_fraction_hint') }}</p>
                    <FormError :errors="errors" field="allows_fraction" />
                </div>
                <label v-if="editing" class="flex items-center gap-2 text-sm" style="color:var(--body)">
                    <button type="button" class="switch" :class="{ on: form.is_active }" :aria-pressed="form.is_active" @click="form.is_active = !form.is_active"></button>
                    {{ t('common.active') }}
                </label>
                <div class="flex justify-end gap-2 pt-2">
                    <button type="button" class="btn btn-ghost" :disabled="saving" @click="showModal = false">{{ t('common.cancel') }}</button>
                    <button type="submit" class="btn btn-accent" :disabled="saving">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </form>
        </Dialog>
    </div>
</template>
