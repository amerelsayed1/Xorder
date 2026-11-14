<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const isFull = ref(false)

function sync() {
    isFull.value = !!document.fullscreenElement
}

async function toggle() {
    try {
        if (document.fullscreenElement) {
            await document.exitFullscreen()
        } else {
            await document.documentElement.requestFullscreen()
        }
    } catch {
        // Fullscreen can be blocked (e.g. no user gesture / iframe policy); ignore.
    }
}

onMounted(() => document.addEventListener('fullscreenchange', sync))
onBeforeUnmount(() => document.removeEventListener('fullscreenchange', sync))
</script>

<template>
    <button
        type="button"
        class="fs-trigger"
        :aria-label="isFull ? t('common.exit_fullscreen') : t('common.enter_fullscreen')"
        :title="isFull ? t('common.exit_fullscreen') : t('common.enter_fullscreen')"
        @click="toggle"
    >
        <i :class="isFull ? 'pi pi-window-minimize' : 'pi pi-window-maximize'" aria-hidden="true" />
    </button>
</template>

<style scoped>
.fs-trigger {
    position: relative; display: inline-flex; align-items: center; justify-content: center;
    width: 40px; height: 40px; border-radius: 50%; border: none; cursor: pointer;
    background: transparent; color: var(--p-text-color);
}
.fs-trigger:hover { background: var(--p-surface-100); }
.fs-trigger i { font-size: 18px; }
</style>
