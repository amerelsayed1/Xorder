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
    // Optional free-text field (see confirmWithInput). Empty label = no field.
    inputLabel: '',
    inputPlaceholder: '',
    inputMaxlength: 255,
    inputValue: '',
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

// Same dialog with an optional text field (e.g. a cancellation reason).
// Resolves to the trimmed text ('' when left empty) on confirm, or null when
// the user backs out — so callers can tell "no reason" from "didn't confirm".
export async function confirmWithInput(options = {}) {
    const ok = await confirm({ inputValue: '', ...options })
    return ok ? String(confirmState.inputValue || '').trim() : null
}
