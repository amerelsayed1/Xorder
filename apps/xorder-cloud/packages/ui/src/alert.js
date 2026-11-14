import { reactive } from 'vue'

// Single global alert-dialog state. Call `alert('message')` (or `alert({ title,
// message, variant })`) from anywhere and optionally await it — the promise
// resolves when the user dismisses. <AlertDialog /> (mounted once in App.vue)
// renders it. Drop-in replacement for the native window.alert().
const defaults = {
    open: false,
    title: '',
    message: '',
    okText: '',
    variant: 'error', // 'error' | 'success' | 'info'
}

export const alertState = reactive({ ...defaults })

let resolver = null

export function alert(messageOrOptions = {}) {
    const options = typeof messageOrOptions === 'string'
        ? { message: messageOrOptions }
        : messageOrOptions
    return new Promise((resolve) => {
        resolver = resolve
        Object.assign(alertState, defaults, options, { open: true })
    })
}

export function resolveAlert() {
    if (!alertState.open) return
    alertState.open = false
    const r = resolver
    resolver = null
    r?.()
}
