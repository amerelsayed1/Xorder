<script setup>
import { reactive, computed, watch } from 'vue'
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
            always: !!d.always, // open 24 hours
            open: d.open || '09:00',
            close: d.close || '23:00',
        }
    }
}
hydrate(props.modelValue)

function setClosed(day, val) {
    state[day].closed = val
}

// One global "open 24 hours" switch for the whole restaurant, represented as
// every day being always-open. When on, the per-day rows are hidden; turning it
// off restores each day's previously-entered open/close times.
const open24_7 = computed(() => DAYS.every((d) => state[d].always))
function toggle24_7(val) {
    for (const day of DAYS) {
        state[day].always = val
        if (val) state[day].closed = false
    }
}

// Signature of the value we last emitted, so we can distinguish genuinely new
// external data from the echo of our own update:modelValue.
let lastEmitted = ''

// Re-hydrate only when the parent pushes genuinely new data (e.g. the async
// profile load, empty → populated). Skipping our own echo is what prevents the
// edit → emit → v-model → watch → hydrate → emit … infinite loop that froze the
// editor on every keystroke.
watch(() => props.modelValue, (value) => {
    if (!value || !Object.keys(value).length) return
    if (JSON.stringify(value) === lastEmitted) return
    hydrate(value)
})

watch(state, () => {
    // Emit a plain object keyed by day → { closed, always, open, close }.
    const out = {}
    for (const day of DAYS) out[day] = { ...state[day] }
    lastEmitted = JSON.stringify(out)
    emit('update:modelValue', out)
}, { deep: true })
</script>

<template>
    <div class="hours-editor">
        <!-- Global 24/7 switch. When on, individual days are hidden. -->
        <label class="hours-editor-global">
            <input type="checkbox" :checked="open24_7" :disabled="disabled" @change="toggle24_7($event.target.checked)" />
            <span>{{ t('restaurant.open_24_7') }}</span>
        </label>

        <template v-if="!open24_7">
            <div v-for="day in DAYS" :key="day" class="hours-editor-row" :class="{ 'is-off': state[day].closed }">
                <span class="hours-editor-day">{{ t('restaurant.days.' + day) }}</span>

                <!-- dir=ltr so the range always reads open → close (09:00 – 23:00),
                     matching the public info modal instead of flipping under RTL. -->
                <div class="hours-editor-times" dir="ltr">
                    <template v-if="!state[day].closed">
                        <input v-model="state[day].open" type="time" class="input hours-time-input" :disabled="disabled" dir="ltr" />
                        <span class="hours-editor-sep">–</span>
                        <input v-model="state[day].close" type="time" class="input hours-time-input" :disabled="disabled" dir="ltr" />
                    </template>
                    <span v-else class="hours-editor-closed">{{ t('restaurant.day_closed') }}</span>
                </div>

                <label class="hours-editor-toggle">
                    <input type="checkbox" :checked="state[day].closed" :disabled="disabled" @change="setClosed(day, $event.target.checked)" />
                    <span>{{ t('restaurant.day_closed') }}</span>
                </label>
            </div>
        </template>
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

.hours-editor-global {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 12px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--card);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    width: fit-content;
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
