<script setup>
import { watch, onUnmounted, computed, nextTick, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { alertState, resolveAlert } from './alert'
import Icon from './Icon.vue'

const { t } = useI18n()
const okButton = ref(null)

const iconName = computed(() => {
    if (alertState.variant === 'success') return 'check'
    if (alertState.variant === 'info') return 'info'
    return 'alert'
})

function onKey(e) {
    if (!alertState.open) return
    if (e.key === 'Escape' || e.key === 'Enter') {
        e.preventDefault()
        resolveAlert()
    }
}

watch(() => alertState.open, (open) => {
    if (open) {
        window.addEventListener('keydown', onKey)
        nextTick(() => okButton.value?.focus())
    } else {
        window.removeEventListener('keydown', onKey)
    }
})
onUnmounted(() => window.removeEventListener('keydown', onKey))
</script>

<template>
    <Teleport to="body">
        <Transition name="ad">
            <div v-if="alertState.open" class="ad-overlay" @click.self="resolveAlert()">
                <div
                    class="ad-card"
                    role="alertdialog"
                    aria-modal="true"
                    aria-labelledby="alert-title"
                    aria-describedby="alert-message"
                >
                    <div class="ad-icon" :class="`ad-icon-${alertState.variant}`">
                        <Icon :name="iconName" :size="22" />
                    </div>
                    <h3 id="alert-title" class="ad-title">{{ alertState.title || t('common.error') }}</h3>
                    <p v-if="alertState.message" id="alert-message" class="ad-message">{{ alertState.message }}</p>
                    <div class="ad-actions">
                        <button
                            ref="okButton"
                            class="ad-btn"
                            :class="`ad-btn-${alertState.variant}`"
                            @click="resolveAlert()"
                        >
                            {{ alertState.okText || t('common.ok') }}
                        </button>
                    </div>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>

<style scoped>
.ad-overlay { position: fixed; inset: 0; z-index: 100; display: grid; place-items: center; padding: 20px;
    background: rgba(14, 16, 24, .5); backdrop-filter: blur(3px); }
.ad-card { width: 100%; max-width: 400px; background: #fff; border-radius: 18px; padding: 26px 26px 22px;
    text-align: center; box-shadow: 0 30px 70px -20px rgba(14, 16, 24, .45); font-family: 'Tajawal', ui-sans-serif, system-ui, sans-serif; }
.ad-icon { width: 54px; height: 54px; border-radius: 50%; display: grid; place-items: center; margin: 0 auto 16px; }
.ad-icon-error { background: #fdecea; color: #d83a2a; }
.ad-icon-success { background: #e7f6ec; color: #1a9d52; }
.ad-icon-info { background: #fef0d9; color: #d9850a; }
.ad-title { font-size: 19px; font-weight: 700; color: #20242f; }
.ad-message { font-size: 15px; line-height: 1.55; color: #5a606e; margin-top: 8px; white-space: pre-line; }
.ad-actions { display: flex; gap: 10px; margin-top: 24px; }
.ad-btn { flex: 1; height: 44px; border-radius: 11px; font-size: 15px; font-weight: 600; cursor: pointer;
    border: 1px solid transparent; transition: background .15s, border-color .15s; font-family: inherit; color: #fff; }
.ad-btn-error { background: #d83a2a; }
.ad-btn-error:hover { background: #be3022; }
.ad-btn-success { background: #1a9d52; }
.ad-btn-success:hover { background: #158445; }
.ad-btn-info { background: #f89a06; }
.ad-btn-info:hover { background: #d9850a; }

.ad-enter-active, .ad-leave-active { transition: opacity .18s ease; }
.ad-enter-from, .ad-leave-to { opacity: 0; }
.ad-enter-active .ad-card { transition: transform .18s ease; }
.ad-enter-from .ad-card { transform: translateY(8px) scale(.97); }
</style>
