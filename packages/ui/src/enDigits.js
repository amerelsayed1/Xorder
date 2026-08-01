// Force English (ASCII) digits in phone & money inputs across every app.
//
// Arabic keyboards emit Arabic-Indic (٠..٩ = U+0660–0669) or Persian (۰..۹ =
// U+06F0–06F9) digits. Those break phone matching and money parsing, so we
// normalize them to ASCII as the user types. Free-text fields (names,
// descriptions) are left untouched so Arabic copy keeps its native numerals —
// only numeric-intent inputs are normalized:
//   • type="tel" | type="number"
//   • inputmode="tel" | "numeric" | "decimal"
//   • any input/textarea explicitly opted in with a `data-en-digits` attribute
//
// `installEnDigits()` wires a single delegated listener per app (call it once
// from main.js). It runs in the capture phase so the value is already ASCII by
// the time Vue's v-model handler reads it — no double-dispatch needed.

const ARABIC_INDIC = /[٠-٩]/g // ٠ ١ ٢ … ٩
const EXTENDED_ARABIC = /[۰-۹]/g // ۰ ۱ ۲ … ۹ (Persian/Urdu)
const HAS_NON_ASCII_DIGIT = /[٠-٩۰-۹]/

/** Convert any Arabic-Indic / Persian digits in a string to ASCII 0-9. */
export function toEnDigits(value) {
    if (value == null) return value
    return String(value)
        .replace(ARABIC_INDIC, (d) => d.charCodeAt(0) - 0x0660)
        .replace(EXTENDED_ARABIC, (d) => d.charCodeAt(0) - 0x06f0)
}

const NUMERIC_TYPES = new Set(['tel', 'number'])
const NUMERIC_MODES = new Set(['tel', 'numeric', 'decimal'])

function wantsEnDigits(el) {
    if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) return false
    if (el.hasAttribute('data-en-digits')) return true
    const type = (el.getAttribute('type') || 'text').toLowerCase()
    if (NUMERIC_TYPES.has(type)) return true
    const mode = (el.inputMode || el.getAttribute('inputmode') || '').toLowerCase()
    return NUMERIC_MODES.has(mode)
}

/**
 * Attach the global digit normalizer. Returns a disposer.
 * @param {Document|HTMLElement} [target] scope to listen on (defaults to document).
 */
export function installEnDigits(target = typeof document !== 'undefined' ? document : null) {
    if (!target) return () => {}

    const onInput = (e) => {
        if (e.isComposing) return // don't disturb an in-flight IME composition
        const el = e.target
        if (!wantsEnDigits(el)) return
        const converted = toEnDigits(el.value)
        if (converted === el.value) return
        // 1:1 char mapping, so caret offsets stay valid across the swap.
        let start = null
        let end = null
        try {
            start = el.selectionStart
            end = el.selectionEnd
        } catch {
            /* selection API is unavailable on number/email inputs */
        }
        el.value = converted
        if (start != null) {
            try {
                el.setSelectionRange(start, end)
            } catch {
                /* noop */
            }
        }
    }

    // number/email inputs silently drop Arabic-Indic digits *before* `input`
    // fires, so `onInput` never sees them. Intercept the insertion and re-add
    // the ASCII form (append covers the common left-to-right typing case).
    const onBeforeInput = (e) => {
        const el = e.target
        if (!el || el.tagName !== 'INPUT') return
        const type = (el.getAttribute('type') || '').toLowerCase()
        if (type !== 'number' && type !== 'email') return
        if (!e.data || !HAS_NON_ASCII_DIGIT.test(e.data)) return
        e.preventDefault()
        el.value = toEnDigits(el.value) + toEnDigits(e.data)
        el.dispatchEvent(new Event('input', { bubbles: true }))
    }

    target.addEventListener('input', onInput, true)
    target.addEventListener('beforeinput', onBeforeInput, true)
    return () => {
        target.removeEventListener('input', onInput, true)
        target.removeEventListener('beforeinput', onBeforeInput, true)
    }
}

export default installEnDigits
