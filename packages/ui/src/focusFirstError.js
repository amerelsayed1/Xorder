/**
 * Scroll the first server-side validation error into view, and focus its field.
 *
 * A long form's submit button is at the bottom and its first bad field is
 * usually off the top of the screen — so a 422 that only re-renders the
 * messages looks, from where the operator is standing, like a button that did
 * nothing. This is what turns it back into an answer.
 *
 * Finds the message rendered by `FormError` (which tags itself with
 * `data-field-error`) rather than the input: these forms label with a `<span>`
 * and carry no `name` attributes, so the message is the only element that knows
 * which field it belongs to.
 *
 * Call it after assigning `errors.value` and awaiting `nextTick()` — the
 * messages do not exist in the DOM until Vue has re-rendered them.
 *
 * @param {Object} errors  The `errors` bag from a 422 response.
 * @param {string[]} [order]  Field names in the order they appear on screen.
 *   Object key order follows the SERVER's rules array, which need not match the
 *   form's layout; pass this when the two differ and the topmost error matters.
 */
export function focusFirstError(errors, order = []) {
    const keys = Object.keys(errors || {})
    if (!keys.length) return

    const first = order.find((field) => keys.includes(field)) || keys[0]
    const message = document.querySelector(`[data-field-error="${CSS.escape(first)}"]`)
    if (!message) return

    // `center`, not `start`: a field scrolled to the very top of the viewport
    // sits under whatever sticky header the page has, and the operator reads a
    // message whose field they cannot see.
    message.scrollIntoView({ behavior: 'smooth', block: 'center' })

    // Focus the control the message belongs to, so the fix is one keystroke
    // away. It is the nearest field in the same labelled block.
    const field = message.closest('label, .block')?.querySelector('input, select, textarea')
    field?.focus({ preventScroll: true })
}
