<script setup>
// A3 / CB-08 — who the receipt says sold the food.
//
// One page, two owners, said out loud in the markup: the registration number
// is a fact about the TAXPAYER and is stored on the restaurant (it is also the
// only place it has ever been stored, and until now nothing could set it —
// CLOUD_WAVE1 deviation 6); everything else is a fact about the BRANCH and
// lives in that branch's receipt profile. They save through their own
// endpoints, each writing what it owns.
//
// Gated exactly as the money config is: the route opens on settings.view and
// every write additionally needs settings.update, which is what the server
// stacks under feature:pos.
import { ref, reactive, computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@xorder/api-client/api.js'
import { withMinDuration } from '../../lib/minLoading.js'
import { useCaps } from '../../lib/useCaps.js'
import { pickLocalized } from '@xorder/ui/localize.js'
import ErrorState from '@xorder/ui/ErrorState.vue'
import FormError from '@xorder/ui/FormError.vue'
import SettingsHeader from './settings/SettingsHeader.vue'
import { alert } from '@xorder/ui/alert.js'

const { t, locale } = useI18n()
const { canUpdate } = useCaps('settings')

const loading = ref(true)
const failed = ref(false)
const branches = ref([])
const profiles = ref([])
const selectedBranchId = ref(null)

// The taxpayer's number, restaurant-level. Kept apart from the branch form
// because it saves somewhere else.
const trn = ref('')
const trnSaved = ref('')
const trnSaving = ref(false)
const trnErrors = ref({})

const saving = ref(false)
const errors = ref({})

// Every field the branch profile authors, in the order the form shows them.
// `revision` rides along so a stale save is refused by the server instead of
// overwriting whoever saved first.
const form = reactive({
    trade_name: '', activity_code: '', branch_code: '',
    country: 'EG', governate: '', region_city: '', street: '',
    building_number: '', postal_code: '', floor: '', room: '',
    landmark: '', additional_info: '', phone: '',
    header_note: '', footer_note: '',
    revision: 0,
})

const selected = computed(() => profiles.value.find((p) => p.branch_id === selectedBranchId.value) || null)
const branchName = (id) => {
    const b = branches.value.find((x) => x.id === id)
    return b ? pickLocalized(b, 'name', locale.value) : `#${id}`
}

async function load() {
    loading.value = true
    failed.value = false
    try {
        const [receipts, br] = await withMinDuration(Promise.all([
            api.get('api/dashboard/receipt-profiles'),
            // Names for the picker. Best-effort: a settings-only account may
            // hold settings.view without branches.view, and that must degrade
            // to "#id", not fail the page.
            api.get('api/dashboard/branches').catch(() => null),
        ]))
        profiles.value = receipts.data.data.profiles
        trn.value = receipts.data.data.registration_number || ''
        trnSaved.value = trn.value
        if (br) branches.value = br.data.data
        if (!profiles.value.some((p) => p.branch_id === selectedBranchId.value)) {
            selectedBranchId.value = profiles.value[0]?.branch_id ?? null
        }
        hydrate()
    } catch (err) {
        failed.value = true
    } finally {
        loading.value = false
    }
}
onMounted(load)

// Switching branch discards nothing of value: an unsaved edit belongs to the
// branch it was typed against, so it is reloaded from the server's copy.
watch(selectedBranchId, hydrate)

function hydrate() {
    const p = selected.value
    errors.value = {}
    for (const key of Object.keys(form)) {
        if (key === 'revision') continue
        form[key] = p?.[key] ?? ''
    }
    form.country = p?.country || 'EG'
    form.revision = p?.revision ?? 0
}

async function save() {
    if (saving.value || !selectedBranchId.value) return
    errors.value = {}
    saving.value = true
    try {
        const { data } = await api.put(`api/dashboard/receipt-profiles/${selectedBranchId.value}`, { ...form })
        profiles.value = profiles.value.map((p) => (p.branch_id === data.data.branch_id ? data.data : p))
        hydrate()
        alert(t('common.saved'))
    } catch (err) {
        if (err.response?.status === 409) {
            // Somebody else saved while this form was open. Their version wins
            // and is loaded, rather than silently discarding their typing.
            alert(err.response.data?.message || t('common.error'))
            await load()
            return
        }
        errors.value = err.response?.data?.errors || {}
        if (!Object.keys(errors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        saving.value = false
    }
}

async function saveTrn() {
    if (trnSaving.value) return
    trnErrors.value = {}
    trnSaving.value = true
    try {
        await api.put('api/dashboard/restaurant', { tax_registration_number: trn.value })
        trnSaved.value = trn.value
        // Every branch profile shows it, so refresh what the page displays.
        profiles.value = profiles.value.map((p) => ({ ...p, registration_number: trn.value }))
        alert(t('common.saved'))
    } catch (err) {
        trnErrors.value = err.response?.data?.errors || {}
        if (!Object.keys(trnErrors.value).length) alert(err.response?.data?.message || t('common.error'))
    } finally {
        trnSaving.value = false
    }
}
</script>

<template>
    <div class="set-stack-lg">
        <SettingsHeader :title="t('nav.pos_receipt')" :desc="t('pos_receipt.subtitle')" />

        <!-- This is not a dashboard preference: it is the header printed on a
             customer's slip and the seller block of an e-receipt. Say it once,
             at the top, rather than on every save. -->
        <div class="set-banner">
            <i class="pi pi-info-circle" aria-hidden="true"></i>
            <span>{{ t('pos_receipt.sync_note') }}</span>
        </div>

        <p v-if="!canUpdate" class="set-desc">{{ t('pos_receipt.read_only') }}</p>

        <ErrorState v-if="failed" :message="t('common.error')" @retry="load" />

        <template v-else>
            <!-- ------------------------------------------------- taxpayer -->
            <section class="set-card">
                <div class="set-card-head">
                    <div class="set-card-head-text">
                        <span class="set-card-title">{{ t('pos_receipt.business') }}</span>
                        <span class="set-card-desc">{{ t('pos_receipt.business_hint') }}</span>
                    </div>
                </div>

                <div v-if="loading" class="set-card-body">
                    <div class="set-skel" style="height: 44px"></div>
                </div>
                <div v-else class="set-card-body">
                    <label class="block" style="max-width: 320px">
                        <span class="label">{{ t('pos_receipt.registration_number') }}</span>
                        <input v-model="trn" class="input" dir="ltr" inputmode="numeric" data-en-digits
                            maxlength="32" placeholder="123456789" :disabled="!canUpdate" />
                        <p class="page-sub" style="margin-top:4px">{{ t('pos_receipt.registration_number_hint') }}</p>
                        <FormError :errors="trnErrors" field="tax_registration_number" />
                    </label>
                    <div v-if="canUpdate" class="flex gap-3">
                        <button type="button" class="btn btn-accent" :disabled="trnSaving || trn === trnSaved" @click="saveTrn">
                            {{ trnSaving ? t('common.saving') : t('common.save') }}
                        </button>
                    </div>
                </div>
            </section>

            <!-- --------------------------------------------- the branch -->
            <section class="set-card">
                <div class="set-card-head">
                    <div class="set-card-head-text">
                        <span class="set-card-title">{{ t('pos_receipt.branch') }}</span>
                        <span class="set-card-desc">{{ t('pos_receipt.branch_hint') }}</span>
                    </div>
                </div>

                <div v-if="loading" class="set-card-body">
                    <div v-for="n in 4" :key="n" class="set-skel" style="height: 44px"></div>
                </div>
                <div v-else-if="!profiles.length" class="set-empty">
                    <span class="set-empty-title">{{ t('pos_receipt.no_branches') }}</span>
                    <span class="set-empty-hint">{{ t('pos_receipt.no_branches_hint') }}</span>
                </div>
                <form v-else class="set-card-body" @submit.prevent="save">
                    <!-- One branch needs no picker; the title already says it. -->
                    <label v-if="profiles.length > 1" class="block" style="max-width: 320px">
                        <span class="label">{{ t('pos_receipt.pick_branch') }}</span>
                        <select v-model="selectedBranchId" class="input">
                            <option v-for="p in profiles" :key="p.branch_id" :value="p.branch_id">
                                {{ branchName(p.branch_id) }}
                            </option>
                        </select>
                    </label>

                    <div class="set-grid-2">
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.trade_name') }}</span>
                            <input v-model="form.trade_name" class="input" maxlength="150"
                                :placeholder="t('pos_receipt.trade_name_placeholder')" :disabled="!canUpdate" />
                            <p class="page-sub" style="margin-top:4px">{{ t('pos_receipt.trade_name_hint') }}</p>
                            <FormError :errors="errors" field="trade_name" />
                        </label>

                        <label class="block">
                            <span class="label">{{ t('pos_receipt.activity_code') }}</span>
                            <input v-model="form.activity_code" class="input" dir="ltr" inputmode="numeric"
                                data-en-digits maxlength="4" placeholder="5610" :disabled="!canUpdate" />
                            <p class="page-sub" style="margin-top:4px">{{ t('pos_receipt.activity_code_hint') }}</p>
                            <FormError :errors="errors" field="activity_code" />
                        </label>

                        <!-- The one field people get wrong: this is the branch
                             as the tax authority registered it, NOT the invoice
                             prefix on the Branches page. -->
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.branch_code') }}</span>
                            <input v-model="form.branch_code" class="input" dir="ltr" maxlength="32"
                                placeholder="0042" :disabled="!canUpdate" />
                            <p class="page-sub" style="margin-top:4px">{{ t('pos_receipt.branch_code_hint') }}</p>
                            <FormError :errors="errors" field="branch_code" />
                        </label>

                        <label class="block">
                            <span class="label">{{ t('pos_receipt.phone') }}</span>
                            <input v-model="form.phone" class="input" dir="ltr" maxlength="32" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="phone" />
                        </label>
                    </div>

                    <p class="set-card-title" style="margin:8px 0 0">{{ t('pos_receipt.address') }}</p>
                    <p class="page-sub" style="margin:0">{{ t('pos_receipt.address_hint') }}</p>

                    <div class="set-grid-2">
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.country') }}</span>
                            <input v-model="form.country" class="input" dir="ltr" maxlength="2"
                                placeholder="EG" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="country" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.governate') }}</span>
                            <input v-model="form.governate" class="input" maxlength="80" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="governate" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.region_city') }}</span>
                            <input v-model="form.region_city" class="input" maxlength="80" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="region_city" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.street') }}</span>
                            <input v-model="form.street" class="input" maxlength="150" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="street" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.building_number') }}</span>
                            <input v-model="form.building_number" class="input" dir="ltr" maxlength="32" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="building_number" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.postal_code') }}</span>
                            <input v-model="form.postal_code" class="input" dir="ltr" maxlength="16" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="postal_code" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.floor') }}</span>
                            <input v-model="form.floor" class="input" maxlength="16" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="floor" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.room') }}</span>
                            <input v-model="form.room" class="input" maxlength="16" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="room" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.landmark') }}</span>
                            <input v-model="form.landmark" class="input" maxlength="150" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="landmark" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.additional_info') }}</span>
                            <input v-model="form.additional_info" class="input" maxlength="255" :disabled="!canUpdate" />
                            <FormError :errors="errors" field="additional_info" />
                        </label>
                    </div>

                    <p class="set-card-title" style="margin:8px 0 0">{{ t('pos_receipt.notes') }}</p>
                    <p class="page-sub" style="margin:0">{{ t('pos_receipt.notes_hint') }}</p>

                    <div class="set-grid-2">
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.header_note') }}</span>
                            <textarea v-model="form.header_note" class="input" rows="2" maxlength="500" :disabled="!canUpdate"></textarea>
                            <FormError :errors="errors" field="header_note" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('pos_receipt.footer_note') }}</span>
                            <textarea v-model="form.footer_note" class="input" rows="2" maxlength="500" :disabled="!canUpdate"></textarea>
                            <FormError :errors="errors" field="footer_note" />
                        </label>
                    </div>

                    <div v-if="canUpdate" class="flex gap-3">
                        <button type="submit" class="btn btn-accent" :disabled="saving">
                            {{ saving ? t('common.saving') : t('common.save') }}
                        </button>
                    </div>
                </form>
            </section>
        </template>
    </div>
</template>

<style scoped>
/* Two columns on a wide screen, one on a phone. Logical properties only —
   this page reads right-to-left in Arabic. */
.set-grid-2 {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 14px 18px;
}
</style>
