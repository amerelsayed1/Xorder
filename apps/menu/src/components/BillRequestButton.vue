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
const token = ref('')
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
        const res = await createBillRequest(props.sessionToken, note.value)
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
        <!-- Floating service button; shows the live badge once a request is open. -->
        <button
            class="bill-fab"
            type="button"
            @click="isOpen ? (view = 'status') : openConfirm()"
        >
            <span class="bill-fab__icon">🧾</span>
            <span>{{ t('request_bill') }}</span>
            <span v-if="isOpen" class="bill-fab__dot" />
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
                            :disabled="submitting"
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
.bill-fab {
    position: fixed;
    inset-inline-end: 16px;
    bottom: 84px;
    z-index: 55;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 12px 18px;
    border: 0;
    border-radius: 999px;
    background: var(--accent-dark);
    color: #fff;
    font-weight: 700;
    font-size: 14px;
    cursor: pointer;
    box-shadow: 0 12px 30px #00000038;
}
.bill-fab__icon { font-size: 17px; }
.bill-fab__dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #38d16a;
    box-shadow: 0 0 0 3px #ffffff55;
}
.bill-note {
    width: 100%;
    border: 1px solid var(--line);
    border-radius: 12px;
    padding: 10px 12px;
    font: inherit;
    resize: none;
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
