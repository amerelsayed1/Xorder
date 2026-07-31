<script setup>
import { toastState, dismissToast } from './toast'
import Icon from './Icon.vue'

const iconFor = (v) => (v === 'error' ? 'alert' : v === 'info' ? 'info' : 'check')
</script>

<template>
    <Teleport to="body">
        <div class="toast-stack" role="status" aria-live="polite">
            <TransitionGroup name="toast">
                <button
                    v-for="item in toastState.items"
                    :key="item.id"
                    type="button"
                    class="toast"
                    :class="`toast-${item.variant}`"
                    @click="dismissToast(item.id)"
                >
                    <Icon :name="iconFor(item.variant)" :size="18" />
                    <span class="toast-msg">{{ item.message }}</span>
                </button>
            </TransitionGroup>
        </div>
    </Teleport>
</template>

<style scoped>
.toast-stack {
    position: fixed;
    inset-block-end: 20px;
    inset-inline: 0;
    z-index: 120;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 0 16px;
    pointer-events: none;
}
.toast {
    pointer-events: auto;
    display: inline-flex;
    align-items: center;
    gap: 9px;
    max-width: min(92vw, 440px);
    padding: 11px 16px;
    border-radius: 12px;
    font-family: 'Tajawal', ui-sans-serif, system-ui, sans-serif;
    font-size: 14.5px;
    font-weight: 600;
    color: #fff;
    border: none;
    cursor: pointer;
    box-shadow: 0 14px 34px -12px rgba(14, 16, 24, .5);
}
.toast-msg { line-height: 1.4; text-align: start; }
.toast-success { background: #1a9d52; }
.toast-info { background: #f89a06; }
.toast-error { background: #d83a2a; }

.toast-enter-active, .toast-leave-active { transition: opacity .2s ease, transform .2s ease; }
.toast-enter-from, .toast-leave-to { opacity: 0; transform: translateY(10px); }
</style>
