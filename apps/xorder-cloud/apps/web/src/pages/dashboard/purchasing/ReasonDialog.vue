<script setup>
import { ref, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import Dialog from '@xorder/ui/Dialog.vue'
import FormError from '@xorder/ui/FormError.vue'
import Icon from '@xorder/ui/Icon.vue'

// CB-09 slice c. One dialog for every "say why" action on these pages:
// voiding an invoice, voiding a payment, closing an order short. The reason
// is a CODE from a fixed list (the till's lists where it has one), because a
// code can be counted later; `other` needs a note, on the server as here.
const props = defineProps({
    title: { type: String, required: true },
    subtitle: { type: String, default: '' },
    message: { type: String, default: '' },
    reasons: { type: Array, required: true },
    labelPrefix: { type: String, required: true },
    confirmText: { type: String, required: true },
    busy: { type: Boolean, default: false },
    errors: { type: Object, default: () => ({}) },
})
const emit = defineEmits(['submit', 'close'])
const { t } = useI18n()

const reason = ref('')
const note = ref('')
const local = ref({})
const needsNote = computed(() => reason.value === 'other')
const shown = computed(() => ({ ...props.errors, ...local.value }))

// Slice d: a stock entry swaps its reason list with its kind (waste, add,
// take off...). Drop a choice that is no longer offered, and preselect the
// only one when there is one (opening stock, a count).
watch(() => props.reasons, (list) => {
    if (!list.includes(reason.value)) reason.value = list.length === 1 ? list[0] : ''
}, { immediate: true })

function submit() {
    const e = {}
    if (!reason.value) e.reason = [t('purchasing.pick_reason')]
    if (needsNote.value && !note.value.trim()) e.note = [t('purchasing.note_required')]
    local.value = e
    if (Object.keys(e).length) return
    emit('submit', { reason: reason.value, note: note.value.trim() || null })
}
</script>

<template>
    <Dialog :title="title" :subtitle="subtitle" @close="emit('close')">
        <form class="space-y-4" @submit.prevent="submit">
            <p v-if="message" class="text-sm" style="color:var(--body)">{{ message }}</p>
            <!-- Slice d: a stock entry's own fields (item, quantity, cost). -->
            <slot />
            <fieldset class="reason-set">
                <legend class="label">{{ t('purchasing.reason') }}</legend>
                <label v-for="r in reasons" :key="r" class="reason-opt" :class="reason === r ? 'is-on' : ''">
                    <input v-model="reason" type="radio" name="reason" :value="r" class="h-4 w-4" />
                    {{ t(labelPrefix + '.' + r) }}
                </label>
                <FormError :errors="shown" field="reason" />
            </fieldset>
            <label class="block">
                <span class="label">{{ needsNote ? t('purchasing.note_required_label') : t('purchasing.note_optional') }}</span>
                <textarea v-model="note" class="input" rows="2" maxlength="1000"></textarea>
                <FormError :errors="shown" field="note" />
            </label>
            <div class="reason-actions">
                <button type="button" class="btn btn-ghost" :disabled="busy" @click="emit('close')">{{ t('common.cancel') }}</button>
                <button type="submit" class="btn btn-accent" :disabled="busy">
                    <Icon v-if="busy" name="loading" :size="16" class="animate-spin" />
                    {{ confirmText }}
                </button>
            </div>
        </form>
    </Dialog>
</template>

<style scoped>
/* Presentation only: theme variables and the PrimeVue primary scale; no new hex values. */
.note { display: flex; align-items: flex-start; gap: 10px; padding: 12px 14px; border-radius: 12px; font-size: 14.5px; line-height: 1.5; }
.note > i { margin-top: 3px; flex: none; }
.reason-set { display: grid; gap: 8px; }
.reason-opt { display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 8px 12px; border: 1px solid var(--line); border-radius: 10px; font-size: 15px; color: var(--ink); cursor: pointer; transition: background .15s, border-color .15s; }
.reason-opt:hover { background: var(--page); }
.reason-opt.is-on { border-color: var(--accent); background: var(--accent-soft); }
.reason-opt input { accent-color: var(--accent); }
.reason-actions { display: flex; justify-content: flex-end; gap: 8px; padding-top: 8px; }
.reason-actions .btn { min-height: 44px; }
</style>
