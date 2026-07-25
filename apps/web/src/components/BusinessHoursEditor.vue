<script setup>
import { reactive, watch } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue'])

// Saturday-first to match the Arabic week; each row keeps its own weekday key.
const DAYS = ['sat', 'sun', 'mon', 'tue', 'wed', 'thu', 'fri']

// Local editable copy so blank/partial incoming data still renders 7 controlled
// rows. Every day is present with a sane default (09:00–23:00, open).
const state = reactive({})
function hydrate(value) {
    for (const day of DAYS) {
        const d = (value && value[day]) || {}
        state[day] = {
            closed: !!d.closed,
            open: d.open || '09:00',
            close: d.close || '23:00',
        }
    }
}
hydrate(props.modelValue)

// Re-hydrate when the parent loads data asynchronously (empty → populated).
watch(() => props.modelValue, (value) => {
    if (value && Object.keys(value).length) hydrate(value)
})

watch(state, () => {
    // Emit a plain object keyed by day → { closed, open, close }.
    const out = {}
    for (const day of DAYS) out[day] = { ...state[day] }
    emit('update:modelValue', out)
}, { deep: true })
</script>

<template>
    <div class="hours-editor">
        <div v-for="day in DAYS" :key="day" class="hours-editor-row" :class="{ 'is-off': state[day].closed }">
            <span class="hours-editor-day">{{ t('restaurant.days.' + day) }}</span>

            <div class="hours-editor-times">
                <template v-if="!state[day].closed">
                    <input v-model="state[day].open" type="time" class="input hours-time-input" :disabled="disabled" dir="ltr" />
                    <span class="hours-editor-sep">–</span>
                    <input v-model="state[day].close" type="time" class="input hours-time-input" :disabled="disabled" dir="ltr" />
                </template>
                <span v-else class="hours-editor-closed">{{ t('restaurant.day_closed') }}</span>
            </div>

            <label class="hours-editor-toggle">
                <input v-model="state[day].closed" type="checkbox" :disabled="disabled" />
                <span>{{ t('restaurant.day_closed') }}</span>
            </label>
        </div>
    </div>
</template>

<style scoped>
.hours-editor {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 6px;
}

.hours-editor-row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 12px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--card);
}

.hours-editor-row.is-off {
    opacity: .7;
}

.hours-editor-day {
    flex: 0 0 96px;
    font-weight: 600;
    font-size: 13px;
}

.hours-editor-times {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 8px;
}

.hours-time-input {
    width: auto;
    min-width: 0;
    flex: 1;
    max-width: 130px;
}

.hours-editor-sep {
    color: var(--muted);
}

.hours-editor-closed {
    color: var(--muted);
    font-size: 13px;
}

.hours-editor-toggle {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: var(--muted);
    cursor: pointer;
    flex: none;
}
</style>
