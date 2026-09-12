<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { useAuth } from '@xorder/api-client/auth.js'
import { withMinDuration } from '../../../lib/minLoading.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import { useMenuLang } from '../../../lib/menuLang.js'
import Dialog from '@xorder/ui/Dialog.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import ErrorState from '@xorder/ui/ErrorState.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { alert } from '@xorder/ui/alert.js'

// CB-09 slice a. One capability, purchase.manage, opens this page AND gates
// every write; there is no view/create/update split, so useCaps() (which
// assumes those four verbs) does not apply. A lapsed subscription hides writes
// but never the list. Hiding is a courtesy: the API 403s regardless.
const { t, locale } = useI18n()
const auth = useAuth()
const canWrite = computed(() => auth.can('purchase.manage') && !auth.isReadOnly)
const { langs, bilingual } = useMenuLang()

const rows = ref([])
const loading = ref(true)
const failed = ref(false)
const search = ref('')
const showRetired = ref(false)

async function load() {
    loading.value = true
    failed.value = false
    try {
        const { data } = await withMinDuration(api.get('api/dashboard/suppliers'))
        rows.value = data.data
    } catch {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

const nameOf = (s) => pickLocalized(s, 'name', locale.value) || s.name_en || s.name_ar || `#${s.id}`

// Active first, then by name in the reader's language. Sorted here rather
// than on the server so the order follows the UI locale.
const visible = computed(() => {
    const q = search.value.trim().toLowerCase()
    return rows.value
        .filter((s) => showRetired.value || s.is_active)
        .filter((s) => !q || [s.name_en, s.name_ar, s.code, s.contact_name, s.phone]
            .some((v) => v && String(v).toLowerCase().includes(q)))
        .sort((a, b) => (b.is_active - a.is_active) || nameOf(a).localeCompare(nameOf(b), locale.value))
})
const retiredCount = computed(() => rows.value.filter((s) => !s.is_active).length)

const termsLabel = (s) => (s.payment_term_days > 0
    ? t('purchasing.terms_days', { n: s.payment_term_days })
    : t('purchasing.terms_on_delivery'))

// ------------------------------------------------------------------ editor
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const saving = ref(false)
const blank = () => ({
    name_en: '', name_ar: '', code: '', contact_name: '', phone: '', email: '',
    address: '', tax_number: '', payment_term_days: 0, notes: '', is_active: true,
})
const form = reactive(blank())

function openCreate() {
    editing.value = null
    errors.value = {}
    Object.assign(form, blank())
    showModal.value = true
}
function openEdit(s) {
    editing.value = s
    errors.value = {}
    Object.assign(form, blank(), fromRow(s))
    showModal.value = true
}

// A supplier is always written whole (the server's update rules equal its
// create rules), so a row can be re-saved from what the list already holds.
function fromRow(s) {
    const out = {}
    for (const key of Object.keys(blank())) out[key] = s[key] ?? blank()[key]
    return out
}
function payload(src) {
    return { ...src, payment_term_days: Number(src.payment_term_days) || 0 }
}

function replaceRow(row) {
    const i = rows.value.findIndex((x) => x.id === row.id)
    if (i === -1) rows.value.push(row)
    else rows.value.splice(i, 1, row)
}

async function save() {
    if (saving.value) return
    saving.value = true
    errors.value = {}
    try {
        const { data } = editing.value
            ? await api.put(`api/dashboard/suppliers/${editing.value.id}`, payload(form))
            : await api.post('api/dashboard/suppliers', payload(form))
        // In place, not a refetch: the response IS the stored record.
        replaceRow(data.data)
        showModal.value = false
    } catch (err) {
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

// Retiring is the only way a supplier leaves the list: later purchases,
// invoices and payments point at it, so nothing is ever deleted.
async function setActive(s, active) {
    if (!active) {
        const ok = await confirm({
            title: t('purchasing.retire_supplier_title'),
            message: t('purchasing.retire_supplier_message', { name: nameOf(s) }),
            confirmText: t('purchasing.retire'),
            cancelText: t('common.cancel'),
        })
        if (!ok) return
    }
    try {
        const { data } = await api.put(`api/dashboard/suppliers/${s.id}`, payload({ ...fromRow(s), is_active: active }))
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
                <h1 class="page-title">{{ t('purchasing.suppliers_title') }}</h1>
                <p class="page-sub">{{ t('purchasing.suppliers_sub') }}</p>
            </div>
            <button v-if="canWrite" type="button" class="btn btn-accent" @click="openCreate">
                <Icon name="plus" :size="16" />{{ t('purchasing.add_supplier') }}
            </button>
        </div>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <div v-if="!loading && rows.length" class="flex flex-wrap items-center gap-3">
                <input v-model="search" class="input" style="max-width: 360px" :placeholder="t('purchasing.search_suppliers')" />
                <label v-if="retiredCount" class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)">
                    <input v-model="showRetired" type="checkbox" class="h-4 w-4" />
                    {{ t('purchasing.show_retired') }} <span class="mono" dir="ltr">({{ retiredCount }})</span>
                </label>
            </div>

            <div class="card overflow-hidden">
                <ListSkeleton v-if="loading" />
                <div v-else-if="!rows.length" class="p-8 text-center space-y-1">
                    <div class="font-medium" style="color:var(--ink)">{{ t('purchasing.none_suppliers') }}</div>
                    <div class="text-sm" style="color:var(--muted)">{{ t('purchasing.none_suppliers_hint') }}</div>
                </div>
                <div v-else-if="!visible.length" class="p-8 text-center text-sm" style="color:var(--muted)">{{ t('purchasing.none_match') }}</div>
                <ul v-else>
                    <li v-for="s in visible" :key="s.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)" :style="s.is_active ? '' : 'opacity:.65'">
                        <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><i class="pi pi-briefcase" aria-hidden="true"></i></div>
                        <div class="flex-1 min-w-0">
                            <div class="font-medium flex flex-wrap items-center gap-2" style="color:var(--ink)">
                                {{ nameOf(s) }}
                                <span v-if="s.code" class="mono text-xs rounded px-1.5 py-0.5" dir="ltr" style="background:var(--page);color:var(--muted)">{{ s.code }}</span>
                            </div>
                            <div class="text-xs truncate" style="color:var(--muted)">
                                <span v-if="s.contact_name">{{ s.contact_name }} · </span>
                                <span v-if="s.phone" class="mono" dir="ltr">{{ s.phone }}</span><span v-if="s.phone"> · </span>
                                {{ termsLabel(s) }}
                            </div>
                        </div>
                        <StatusBadge :value="s.is_active" :label="s.is_active ? t('common.active') : t('purchasing.retired')" />
                        <button v-if="canWrite" type="button" class="icon-btn" :title="t('common.edit')" :aria-label="t('common.edit')" @click="openEdit(s)"><Icon name="edit" :size="17" /></button>
                        <button v-if="canWrite && s.is_active" type="button" class="btn btn-ghost btn-sm" @click="setActive(s, false)">{{ t('purchasing.retire') }}</button>
                        <button v-else-if="canWrite" type="button" class="btn btn-ghost btn-sm" @click="setActive(s, true)">{{ t('purchasing.reactivate') }}</button>
                    </li>
                </ul>
            </div>
            <p v-if="!loading && rows.length" class="text-xs" style="color:var(--muted)">{{ t('purchasing.never_deleted') }}</p>
        </template>

        <Dialog v-if="showModal" :title="editing ? t('purchasing.edit_supplier') : t('purchasing.add_supplier')" @close="showModal = false">
            <form class="space-y-4" @submit.prevent="save">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label v-for="lng in langs" :key="'n' + lng" class="block" :dir="lng === 'ar' ? 'rtl' : 'ltr'">
                        <span class="label">{{ bilingual ? t('common.name_' + lng) : t('common.name') }}</span>
                        <input v-model="form['name_' + lng]" class="input" maxlength="160" />
                        <FormError :errors="errors" :field="'name_' + lng" />
                    </label>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('purchasing.code') }}</span>
                        <input v-model="form.code" class="input mono" dir="ltr" maxlength="40" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.code_hint') }}</span>
                        <FormError :errors="errors" field="code" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.contact_name') }}</span>
                        <input v-model="form.contact_name" class="input" maxlength="160" />
                        <FormError :errors="errors" field="contact_name" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.phone') }}</span>
                        <input v-model="form.phone" class="input" dir="ltr" inputmode="tel" data-en-digits maxlength="40" />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.email') }}</span>
                        <input v-model="form.email" type="email" class="input" dir="ltr" maxlength="255" />
                        <FormError :errors="errors" field="email" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.tax_number') }}</span>
                        <input v-model="form.tax_number" class="input mono" dir="ltr" inputmode="numeric" data-en-digits maxlength="9" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.tax_number_hint') }}</span>
                        <FormError :errors="errors" field="tax_number" /></label>
                    <label class="block"><span class="label">{{ t('purchasing.payment_terms') }}</span>
                        <input v-model.number="form.payment_term_days" type="number" min="0" max="3650" step="1" class="input" dir="ltr" />
                        <span class="text-xs" style="color:var(--muted)">{{ t('purchasing.payment_terms_hint') }}</span>
                        <FormError :errors="errors" field="payment_term_days" /></label>
                </div>
                <label class="block"><span class="label">{{ t('purchasing.address') }}</span>
                    <textarea v-model="form.address" class="input" rows="2" maxlength="1000"></textarea>
                    <FormError :errors="errors" field="address" /></label>
                <label class="block"><span class="label">{{ t('purchasing.notes') }}</span>
                    <textarea v-model="form.notes" class="input" rows="2" maxlength="2000"></textarea>
                    <FormError :errors="errors" field="notes" /></label>
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
