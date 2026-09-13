<script setup>
import { ref, computed } from 'vue'
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
            <p v-if="message" class="text-sm" style="color:var(--muted)">{{ message }}</p>
            <fieldset class="space-y-2">
                <legend class="label">{{ t('purchasing.reason') }}</legend>
                <label v-for="r in reasons" :key="r" class="flex items-center gap-2 text-sm cursor-pointer" style="color:var(--body)">
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
            <div class="flex justify-end gap-2 pt-2">
                <button type="button" class="btn btn-ghost" :disabled="busy" @click="emit('close')">{{ t('common.cancel') }}</button>
                <button type="submit" class="btn btn-accent" :disabled="busy">
                    <Icon v-if="busy" name="loading" :size="16" class="animate-spin" />
                    {{ confirmText }}
                </button>
            </div>
        </form>
    </Dialog>
</template>
