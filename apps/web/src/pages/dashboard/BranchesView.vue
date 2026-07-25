<script setup>
import { ref, reactive, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { collectPhoneErrors } from '../../lib/phone.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import Modal from '@xorder/ui/Modal.vue'
import ListSkeleton from '@xorder/ui/ListSkeleton.vue'
import StatusBadge from '@xorder/ui/StatusBadge.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useAuth } from '@xorder/api-client/auth.js'

const { t, locale } = useI18n()
const auth = useAuth()
const rows = ref([])
const loading = ref(true)
const saving = ref(false)
const showModal = ref(false)
const editing = ref(null)
const errors = ref({})
const blank = () => ({ name_en: '', name_ar: '', address: '', phone: '', whatsapp_number: '', opening_hours: '', map_url: '', is_open: true, is_active: true })
const form = reactive(blank())

async function load() {
    loading.value = true
    const { data } = await withMinDuration(api.get('api/dashboard/branches'))
    rows.value = data.data
    loading.value = false
}
onMounted(load)

function openCreate() {
    editing.value = null; errors.value = {}
    Object.assign(form, blank())
    showModal.value = true
}
function openEdit(b) {
    editing.value = b; errors.value = {}
    Object.assign(form, blank(), {
        name_en: b.name_en || '', name_ar: b.name_ar || '', address: b.address || '',
        phone: b.phone || '', whatsapp_number: b.whatsapp_number || '',
        opening_hours: b.opening_hours || '', map_url: b.map_url || '',
        is_open: b.is_open, is_active: b.is_active,
    })
    showModal.value = true
}
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
        if (editing.value) await api.put(`api/dashboard/branches/${editing.value.id}`, form)
        else await api.post('api/dashboard/branches', form)
        showModal.value = false
        await load()
    } catch (err) { errors.value = err.response?.data?.errors || {} }
    finally { saving.value = false }
}
async function toggleOpen(b) {
    await ensureCsrf()
    await api.patch(`api/dashboard/branches/${b.id}/status`, { is_open: !b.is_open })
    b.is_open = !b.is_open
}
async function remove(b) {
    const ok = await confirm({
        title: t('common.delete'),
        message: t('common.confirm_delete'),
        confirmText: t('common.delete'),
        cancelText: t('common.cancel'),
        danger: true,
    })
    if (!ok) return
    try {
        await ensureCsrf()
        await api.delete(`api/dashboard/branches/${b.id}`)
        await load()
    } catch (err) { alert(t('common.delete_failed')) }
}

const branchName = (b) => pickLocalized(b, 'name', locale.value)
</script>

<template>
    <div class="space-y-5">
        <div class="flex items-start justify-between gap-3">
            <div>
                <h1 class="page-title">{{ t('nav.branches') }}</h1>
                <p class="page-sub">{{ t('branch.subtitle', { count: rows.length }) }}</p>
            </div>
            <button v-if="!auth.isReadOnly && auth.hasFeature('multi_branch')" @click="openCreate" class="btn btn-accent"><Icon name="plus" :size="16" />{{ t('common.create') }}</button>
        </div>

        <div class="card overflow-hidden">
            <ListSkeleton v-if="loading" />
            <div v-else-if="!rows.length" class="p-8 text-center" style="color:var(--muted)">{{ t('branch.none') }}</div>
            <ul v-else>
                <li v-for="b in rows" :key="b.id" class="flex items-center gap-3 px-5 py-3 border-t first:border-t-0" style="border-color:var(--line)">
                    <div class="h-11 w-11 rounded-lg grid place-items-center flex-shrink-0" style="background:var(--accent-soft);color:var(--accent)"><Icon name="building" :size="18" /></div>
                    <div class="flex-1 min-w-0">
                        <div class="font-medium" style="color:var(--ink)">{{ branchName(b) }}</div>
                        <div class="text-xs truncate" style="color:var(--muted)">{{ b.address || '—' }}</div>
                    </div>
                    <StatusBadge :value="b.is_open" :label="b.is_open ? t('branch.open') : t('branch.closed')" />
                    <button v-if="!auth.isReadOnly" class="switch" :class="{ on: b.is_open }" :title="t('branch.is_open')" @click="toggleOpen(b)"></button>
                    <button v-if="!auth.isReadOnly" @click="openEdit(b)" class="icon-btn" :title="t('common.edit')"><Icon name="edit" :size="17" /></button>
                    <button v-if="!auth.isReadOnly" @click="remove(b)" class="icon-btn icon-btn-danger" :title="t('common.delete')"><Icon name="trash" :size="17" /></button>
                </li>
            </ul>
        </div>

        <Modal v-if="showModal" :title="editing ? t('common.edit') : t('nav.branches')" @close="showModal = false">
            <div class="space-y-4">
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('common.name_en') }}</span>
                        <input v-model="form.name_en" class="input" />
                        <FormError :errors="errors" field="name_en" /></label>
                    <label class="block" dir="rtl"><span class="label">{{ t('common.name_ar') }}</span>
                        <input v-model="form.name_ar" class="input" />
                        <FormError :errors="errors" field="name_ar" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.address') }}</span>
                    <textarea v-model="form.address" rows="2" class="input"></textarea>
                    <FormError :errors="errors" field="address" /></label>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <label class="block"><span class="label">{{ t('restaurant.phone') }}</span>
                        <input v-model="form.phone" class="input" dir="ltr" />
                        <FormError :errors="errors" field="phone" /></label>
                    <label class="block"><span class="label">{{ t('restaurant.whatsapp') }}</span>
                        <input v-model="form.whatsapp_number" class="input" dir="ltr" />
                        <FormError :errors="errors" field="whatsapp_number" /></label>
                </div>
                <label class="block"><span class="label">{{ t('restaurant.opening_hours') }}</span>
                    <input v-model="form.opening_hours" class="input" :placeholder="t('branch.hours_placeholder')" /></label>
                <label class="block"><span class="label">{{ t('branch.map_url') }}</span>
                    <input v-model="form.map_url" class="input" dir="ltr" placeholder="https://maps.google.com/…" />
                    <FormError :errors="errors" field="map_url" /></label>
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
                <div class="flex justify-end gap-2 pt-2">
                    <button @click="showModal = false" :disabled="saving" class="btn btn-ghost">{{ t('common.cancel') }}</button>
                    <button @click="save" :disabled="saving" class="btn btn-accent">
                        <Icon v-if="saving" name="loading" :size="16" class="animate-spin" />
                        {{ saving ? t('common.saving') : t('common.save') }}
                    </button>
                </div>
            </div>
        </Modal>
    </div>
</template>
