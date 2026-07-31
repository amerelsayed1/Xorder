import { reactive } from 'vue'

// Global, non-blocking toast stack for lightweight *success/info* feedback —
// the counterpart to the blocking alert() dialog, which stays reserved for
// errors that deserve a stop-and-acknowledge. Call `toast('Saved')` (or
// `toast({ message, variant, duration })`) from anywhere; <Toast /> (mounted
// once in App.vue) renders and auto-dismisses them.
export const toastState = reactive({ items: [] })

let seq = 0

export function toast(messageOrOptions = {}) {
    const options = typeof messageOrOptions === 'string'
        ? { message: messageOrOptions }
        : messageOrOptions
    const id = ++seq
    const item = {
        id,
        message: options.message || '',
        variant: options.variant || 'success', // 'success' | 'info' | 'error'
        duration: options.duration ?? 2600,
    }
    toastState.items.push(item)
    if (item.duration > 0) {
        setTimeout(() => dismissToast(id), item.duration)
    }
    return id
}

export function dismissToast(id) {
    const i = toastState.items.findIndex((t) => t.id === id)
    if (i !== -1) toastState.items.splice(i, 1)
}
