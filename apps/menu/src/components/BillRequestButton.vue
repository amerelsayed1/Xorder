<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { createBillRequest, getBillRequest, cancelBillRequest } from '../api.js'

const props = defineProps({
    sessionToken: { type: String, default: '' },
    tableLabel: { type: String, default: '' },
    t: { type: Function, required: true },
})

// The open request token persists per table session so a page refresh keeps
// showing the live status instead of offering to raise a duplicate.
const storageKey = computed(() => `xorder_bill_${props.sessionToken}`)

const view = ref('idle') // idle | confirm | status
const note = ref('')
const chips = ref([])
const token = ref('')

const suggestions = computed(() => {
    const list = props.t('request_bill_suggestions')
    return Array.isArray(list) ? list : []
})

function toggleChip(label) {
    const i = chips.value.indexOf(label)
    if (i >= 0) chips.value.splice(i, 1)
    else chips.value.push(label)
}

// Combine the picked chips with any free-text note into one message for staff.
const composedNote = computed(() => {
    const parts = [...chips.value]
    const extra = note.value.trim()
    if (extra) parts.push(extra)
    return parts.join(' · ')
})
const status = ref('')
const submitting = ref(false)
const errorMsg = ref('')
let pollTimer = null

const OPEN = ['REQUESTED', 'SEEN', 'IN_PROGRESS']
const isOpen = computed(() => OPEN.includes(status.value))
const canCancel = computed(() => status.value === 'REQUESTED')

const confirmText = computed(() =>
    props.t('request_bill_confirm').replace('{label}', props.tableLabel || ''),
)

const statusText = computed(() => {
    switch (status.value) {
        case 'REQUESTED': return props.t('request_bill_pending')
        case 'SEEN': return props.t('request_bill_seen')
        case 'IN_PROGRESS': return props.t('request_bill_in_progress')
        case 'COMPLETED': return props.t('request_bill_done')
        case 'CANCELLED': return props.t('request_bill_cancelled')
        default: return ''
    }
})

function stopPolling() {
    if (pollTimer) {
        clearInterval(pollTimer)
        pollTimer = null
    }
}

function startPolling() {
    stopPolling()
    if (!token.value) return
    pollTimer = setInterval(refreshStatus, 8000)
}

async function refreshStatus() {
    if (!token.value) return
    try {
        const res = await getBillRequest(token.value)
        status.value = res?.data?.status || status.value
        if (!isOpen.value) stopPolling()
    } catch (e) {
        // A 404 means the token is stale — forget it so the button resets.
        if (e.response?.status === 404) forget()
    }
}

function forget() {
    stopPolling()
    localStorage.removeItem(storageKey.value)
    token.value = ''
    status.value = ''
    view.value = 'idle'
}

function openConfirm() {
    errorMsg.value = ''
    note.value = ''
    chips.value = []
    view.value = 'confirm'
}

function close() {
    // Leave a live request tracked; only collapse the panel.
    view.value = 'idle'
}

async function send() {
    if (submitting.value) return
    submitting.value = true
    errorMsg.value = ''
    try {
        const res = await createBillRequest(props.sessionToken, composedNote.value)
        token.value = res?.data?.token || ''
        status.value = res?.data?.status || 'REQUESTED'
        if (token.value) localStorage.setItem(storageKey.value, token.value)
        view.value = 'status'
        if (isOpen.value) startPolling()
    } catch (e) {
        errorMsg.value = e.response?.data?.message || props.t('request_bill_error')
    } finally {
        submitting.value = false
    }
}

async function cancel() {
    if (submitting.value) return
    submitting.value = true
    try {
        const res = await cancelBillRequest(token.value)
        status.value = res?.data?.status || 'CANCELLED'
        stopPolling()
    } catch (e) {
        errorMsg.value = e.response?.data?.message || props.t('request_bill_error')
    } finally {
        submitting.value = false
    }
}

onMounted(async () => {
    const saved = localStorage.getItem(storageKey.value)
    if (saved) {
        token.value = saved
        await refreshStatus()
        if (token.value && isOpen.value) startPolling()
    }
})

onUnmounted(stopPolling)
</script>

<template>
    <div>
        <!-- Secondary table-service action; the sticky bottom action is reserved for the cart. -->
        <button
            class="table-service-button"
            type="button"
            @click="isOpen ? (view = 'status') : openConfirm()"
        >
            <span class="table-service-button__icon">🛎️</span>
            <span>{{ t('call_staff') }}</span>
            <span v-if="isOpen" class="table-service-button__dot" />
        </button>

        <Teleport to="body">
            <div
                v-if="view === 'confirm' || view === 'status'"
                class="modal-backdrop cart-dialog-backdrop"
                @click.self="close"
            >
                <div class="simple-dialog" role="dialog" aria-modal="true">
                    <button class="modal-close" type="button" @click="close">×</button>

                    <template v-if="view === 'confirm'">
                        <h2>{{ t('request_bill_confirm_title') }}</h2>
                        <p style="color:var(--muted);font-size:14px;line-height:1.7;margin:0 0 14px">
                            {{ confirmText }}
                        </p>
                        <div v-if="suggestions.length" class="chip-row">
                            <button
                                v-for="s in suggestions"
                                :key="s"
                                type="button"
                                class="chip"
                                :class="{ 'chip--on': chips.includes(s) }"
                                @click="toggleChip(s)"
                            >
                                {{ s }}
                            </button>
                        </div>
                        <textarea
                            v-model="note"
                            class="bill-note"
                            rows="2"
                            :placeholder="t('request_bill_note_ph')"
                        />
                        <p v-if="errorMsg" class="bill-error">{{ errorMsg }}</p>
                        <button
                            class="dialog-button bill-primary"
                            type="button"
                            :disabled="submitting || !composedNote"
                            @click="send"
                        >
                            {{ submitting ? t('sending') : t('request_bill_send') }}
                        </button>
                        <button class="dialog-button" type="button" @click="close">
                            {{ t('cancel') }}
                        </button>
                    </template>

                    <template v-else>
                        <div class="success-circle" :class="{ 'bill-circle--open': isOpen }">
                            {{ isOpen ? '🧾' : (status === 'COMPLETED' ? '✓' : '—') }}
                        </div>
                        <h2>{{ status === 'COMPLETED' ? t('request_bill_done') : t('request_bill_sent_title') }}</h2>
                        <p style="color:var(--muted);font-size:14px;line-height:1.7;margin:0 0 4px">
                            {{ statusText }}
                        </p>
                        <p v-if="errorMsg" class="bill-error">{{ errorMsg }}</p>
                        <button
                            v-if="canCancel"
                            class="dialog-button"
                            type="button"
                            :disabled="submitting"
                            @click="cancel"
                        >
                            {{ t('request_bill_cancel') }}
                        </button>
                        <button
                            v-if="isOpen"
                            class="dialog-button"
                            type="button"
                            @click="openConfirm"
                        >
                            {{ t('request_service_another') }}
                        </button>
                        <button class="dialog-button bill-primary" type="button" @click="close">
                            {{ t('close') }}
                        </button>
                    </template>
                </div>
            </div>
        </Teleport>
    </div>
</template>

<style scoped>
.table-service-button {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    flex: 0 0 auto;
    padding: 7px 12px;
    border: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
    border-radius: 999px;
    background: color-mix(in srgb, var(--accent) 10%, white);
    color: var(--accent-dark);
    font-weight: 700;
    font-size: 12.5px;
    cursor: pointer;
}
.table-service-button__icon { font-size: 15px; }
.table-service-button__dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #38d16a;
    box-shadow: 0 0 0 3px #ffffff55;
}
.chip-row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin: 0 0 14px;
}
.chip {
    border: 1px solid var(--line);
    border-radius: 999px;
    background: var(--surface, #fff);
    color: var(--text, inherit);
    padding: 7px 14px;
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background .15s, border-color .15s, color .15s;
}
.chip--on {
    background: var(--accent-dark);
    border-color: var(--accent-dark);
    color: #fff;
}
.bill-note {
    width: 100%;
    border: 1px solid var(--line);
    border-radius: 12px;
    padding: 10px 12px;
    font: inherit;
    resize: none;
}
.dialog-button:disabled {
    opacity: .5;
    cursor: not-allowed;
}
.bill-primary {
    background: var(--accent-dark);
    color: #fff;
    border-color: var(--accent-dark);
}
.bill-error {
    color: #b42318;
    font-size: 13px;
    margin: 10px 0 0;
}
.bill-circle--open { background: var(--accent-soft); }
</style>
