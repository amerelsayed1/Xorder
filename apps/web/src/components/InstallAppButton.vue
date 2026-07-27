<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

// The captured `beforeinstallprompt` event; calling .prompt() on it later shows
// the native install dialog. Chromium fires this only when the app meets the
// install criteria (manifest + service worker) and isn't already installed.
let deferred = null
const visible = ref(false)

const DISMISS_KEY = 'pwa-install-dismissed'

function standalone() {
    return window.matchMedia('(display-mode: standalone)').matches
        || window.navigator.standalone === true
}

function onBeforeInstallPrompt(e) {
    e.preventDefault()
    deferred = e
    if (!standalone() && localStorage.getItem(DISMISS_KEY) !== '1') {
        visible.value = true
    }
}

function onInstalled() {
    visible.value = false
    deferred = null
}

async function install() {
    if (!deferred) return
    deferred.prompt()
    await deferred.userChoice.catch(() => {})
    // The prompt can be used only once; drop it and hide either way.
    deferred = null
    visible.value = false
}

function dismiss() {
    visible.value = false
    localStorage.setItem(DISMISS_KEY, '1')
}

onMounted(() => {
    window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt)
    window.addEventListener('appinstalled', onInstalled)
})
onBeforeUnmount(() => {
    window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt)
    window.removeEventListener('appinstalled', onInstalled)
})
</script>

<template>
    <Transition name="pwa-fab">
        <div v-if="visible" class="pwa-fab">
            <button type="button" class="pwa-fab__install" @click="install">
                <i class="pi pi-download" aria-hidden="true" />
                <span>{{ t('pwa.install') }}</span>
            </button>
            <button
                type="button"
                class="pwa-fab__dismiss"
                :aria-label="t('pwa.dismiss')"
                :title="t('pwa.dismiss')"
                @click="dismiss"
            >
                <i class="pi pi-times" aria-hidden="true" />
            </button>
        </div>
    </Transition>
</template>

<style scoped>
.pwa-fab {
    position: fixed;
    bottom: max(1rem, env(safe-area-inset-bottom));
    inset-inline-end: 1rem;
    z-index: 40;
    display: inline-flex;
    align-items: center;
    gap: 2px;
    border-radius: 9999px;
    background: var(--p-primary-color, #f89a06);
    color: var(--p-primary-contrast-color, #fff);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
}
.pwa-fab__install {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 12px 18px;
    border: none;
    background: transparent;
    color: inherit;
    font: inherit;
    font-weight: 700;
    cursor: pointer;
    border-radius: 9999px;
}
.pwa-fab__install i { font-size: 18px; }
.pwa-fab__dismiss {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    margin-inline-end: 6px;
    border: none;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.18);
    color: inherit;
    cursor: pointer;
}
.pwa-fab__dismiss:hover { background: rgba(255, 255, 255, 0.3); }
.pwa-fab__dismiss i { font-size: 13px; }

.pwa-fab-enter-active, .pwa-fab-leave-active { transition: opacity .2s ease, transform .2s ease; }
.pwa-fab-enter-from, .pwa-fab-leave-to { opacity: 0; transform: translateY(12px); }
</style>
