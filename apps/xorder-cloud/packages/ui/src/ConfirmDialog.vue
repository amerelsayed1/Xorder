<script setup>
import { watch, onUnmounted, ref, computed, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { confirmState, resolveConfirm } from './confirm'
import Icon from './Icon.vue'

const { t } = useI18n()
const typed = ref('')
const cancelButton = ref(null)
const confirmButton = ref(null)
const confirmationInput = ref(null)
const freeInput = ref(null)

const needsTypedConfirmation = computed(() => Boolean(confirmState.confirmationText))
const canConfirm = computed(() => {
    if (!needsTypedConfirmation.value) return true
    return typed.value.trim() === String(confirmState.confirmationText)
})

function accept() {
    if (!canConfirm.value) return
    resolveConfirm(true)
}

function onKey(e) {
    if (!confirmState.open) return
    if (e.key === 'Escape') { e.preventDefault(); resolveConfirm(false) }
    else if (e.key === 'Enter' && !confirmState.danger && canConfirm.value) {
        e.preventDefault()
        accept()
    }
}

watch(() => confirmState.open, (open) => {
    if (open) {
        typed.value = ''
        window.addEventListener('keydown', onKey)
        nextTick(() => {
            if (needsTypedConfirmation.value) confirmationInput.value?.focus()
            else if (confirmState.inputLabel) freeInput.value?.focus()
            else if (confirmState.danger) cancelButton.value?.focus()
            else confirmButton.value?.focus()
        })
    } else {
        window.removeEventListener('keydown', onKey)
    }
})
onUnmounted(() => window.removeEventListener('keydown', onKey))
</script>

<template>
    <Teleport to="body">
        <Transition name="cd">
            <div v-if="confirmState.open" class="cd-overlay" @click.self="resolveConfirm(false)">
                <div
                    class="cd-card"
                    role="alertdialog"
                    aria-modal="true"
                    aria-labelledby="confirm-title"
                    aria-describedby="confirm-message"
                >
                    <div class="cd-icon" :class="confirmState.danger ? 'cd-icon-danger' : 'cd-icon-accent'">
                        <Icon :name="confirmState.danger ? 'trash' : 'check'" :size="22" />
                    </div>
                    <h3 id="confirm-title" class="cd-title">{{ confirmState.title || t('common.are_you_sure') }}</h3>
                    <p v-if="confirmState.message" id="confirm-message" class="cd-message">{{ confirmState.message }}</p>
                    <label v-if="needsTypedConfirmation" class="cd-confirm-field">
                        <span>{{ confirmState.confirmationLabel || t('common.type_to_confirm') }}</span>
                        <input
                            ref="confirmationInput"
                            v-model="typed"
                            class="cd-input"
                            autocomplete="off"
                            :placeholder="confirmState.confirmationText"
                        />
                        <small v-if="confirmState.confirmationHint">{{ confirmState.confirmationHint }}</small>
                    </label>
                    <label v-if="confirmState.inputLabel" class="cd-confirm-field">
                        <span>{{ confirmState.inputLabel }}</span>
                        <textarea
                            ref="freeInput"
                            v-model="confirmState.inputValue"
                            class="cd-input cd-textarea"
                            rows="2"
                            :maxlength="confirmState.inputMaxlength"
                            :placeholder="confirmState.inputPlaceholder"
                        ></textarea>
                    </label>
                    <div class="cd-actions">
                        <button ref="cancelButton" class="cd-btn cd-btn-cancel" @click="resolveConfirm(false)">{{ confirmState.cancelText || t('common.cancel') }}</button>
                        <button
                            ref="confirmButton"
                            class="cd-btn"
                            :class="confirmState.danger ? 'cd-btn-danger' : 'cd-btn-accent'"
                            :disabled="!canConfirm"
                            @click="accept"
                        >
                            {{ confirmState.confirmText || t('common.confirm') }}
                        </button>
                    </div>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>

<style scoped>
.cd-overlay { position: fixed; inset: 0; z-index: 100; display: grid; place-items: center; padding: 20px;
    background: rgba(14, 16, 24, .5); backdrop-filter: blur(3px); }
.cd-card { width: 100%; max-width: 400px; background: #fff; border-radius: 18px; padding: 26px 26px 22px;
    text-align: center; box-shadow: 0 30px 70px -20px rgba(14, 16, 24, .45); font-family: 'Tajawal', ui-sans-serif, system-ui, sans-serif; }
.cd-icon { width: 54px; height: 54px; border-radius: 50%; display: grid; place-items: center; margin: 0 auto 16px; }
.cd-icon-danger { background: #fdecea; color: #d83a2a; }
.cd-icon-accent { background: #fef0d9; color: #d9850a; }
.cd-title { font-size: 19px; font-weight: 700; color: #20242f; }
.cd-message { font-size: 15px; line-height: 1.55; color: #5a606e; margin-top: 8px; white-space: pre-line; }
.cd-confirm-field { display: block; text-align: start; margin-top: 18px; }
.cd-confirm-field span { display: block; font-size: 13px; font-weight: 600; color: #20242f; margin-bottom: 7px; }
.cd-confirm-field small { display: block; font-size: 12.5px; line-height: 1.45; color: #6b7280; margin-top: 6px; }
.cd-input { width: 100%; height: 42px; border-radius: 10px; border: 1px solid #d8dbe2;
    padding: 0 12px; color: #20242f; font-size: 15px; outline: none; }
.cd-textarea { height: auto; min-height: 64px; padding: 10px 12px; resize: vertical; font-family: inherit; line-height: 1.45; }
.cd-input:focus { border-color: #f89a06; box-shadow: 0 0 0 3px rgba(248,154,6,.14); }
.cd-actions { display: flex; gap: 10px; margin-top: 24px; }
.cd-btn { flex: 1; height: 44px; border-radius: 11px; font-size: 15px; font-weight: 600; cursor: pointer;
    border: 1px solid transparent; transition: background .15s, border-color .15s; font-family: inherit; }
.cd-btn:disabled { opacity: .45; cursor: not-allowed; }
.cd-btn-cancel { background: #fff; color: #20242f; border-color: #e3e5ea; }
.cd-btn-cancel:hover { border-color: #b9bcc6; }
.cd-btn-danger { background: #d83a2a; color: #fff; }
.cd-btn-danger:hover { background: #be3022; }
.cd-btn-accent { background: #f89a06; color: #fff; }
.cd-btn-accent:hover { background: #d9850a; }

.cd-enter-active, .cd-leave-active { transition: opacity .18s ease; }
.cd-enter-from, .cd-leave-to { opacity: 0; }
.cd-enter-active .cd-card { transition: transform .18s ease; }
.cd-enter-from .cd-card { transform: translateY(8px) scale(.97); }
</style>
