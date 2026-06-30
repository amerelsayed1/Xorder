import { reactive } from 'vue'

// Single global confirm-dialog state. Call `confirm({...})` from anywhere and
// await the boolean result. <ConfirmDialog /> (mounted once in App.vue) renders it.
const defaults = {
    open: false,
    title: '',
    message: '',
    confirmText: '',
    cancelText: '',
    confirmationText: '',
    confirmationLabel: '',
    confirmationHint: '',
    danger: false,
}

export const confirmState = reactive({ ...defaults })

let resolver = null

export function confirm(options = {}) {
    return new Promise((resolve) => {
        resolver = resolve
        Object.assign(confirmState, defaults, options, { open: true })
    })
}

export function resolveConfirm(value) {
    if (!confirmState.open) return
    confirmState.open = false
    const r = resolver
    resolver = null
    r?.(value)
}
