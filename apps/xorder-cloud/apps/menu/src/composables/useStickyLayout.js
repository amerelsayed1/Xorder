import { onMounted, onUnmounted, watch } from 'vue'

/**
 * Publishes the real, measured heights of the fixed topbar, the sticky category
 * toolbar, and the fixed footer as CSS custom properties on <html>:
 *
 *   --topbar-h  height of the fixed topbar
 *   --stack-h   topbar + category toolbar (everything sticky above the content)
 *   --footer-h  height of the fixed footer
 *
 * Every sticky `top`, `scroll-margin`, and bottom gutter in the stylesheet is
 * derived from these, so the layout adapts to the topbar shrinking on mobile,
 * the toolbar reflowing from a row to a stacked column, or the footer growing —
 * without any per-phone magic numbers. Recomputes on element resize (via
 * ResizeObserver), on window resize, and whenever `ready` changes (the observed
 * elements mount/unmount with the payload and the active view).
 *
 * @param {() => unknown} ready reactive getter; re-measure when it changes
 */
export function useStickyLayout(ready) {
    const root = document.documentElement
    const SELECTORS = ['.topbar', '.menu-toolbar', '.fixed-footer']
    let ro = null
    const observed = new WeakSet()

    // Last values written to <html>, so a measurement that changed nothing
    // writes nothing. This is the whole trick: setProperty on the root element
    // invalidates layout for the entire document, and because `measure` is also
    // the ResizeObserver callback, an unconditional write meant every observer
    // tick dirtied the geometry the next tick then had to read back — the
    // read-after-write cycle DevTools reports as a forced reflow (87 ms of one
    // on a real scan). Heights only actually change on rotate, toolbar reflow,
    // or the footer appearing, so nearly every write was a no-op that cost a
    // layout anyway.
    const written = { topbar: null, stack: null, footer: null }

    function write(key, prop, value) {
        if (written[key] === value) return
        written[key] = value
        root.style.setProperty(prop, `${value}px`)
    }

    function measure() {
        // All three reads happen before any write, so they resolve against one
        // layout pass instead of forcing a fresh one each.
        const topbarH = document.querySelector('.topbar')?.offsetHeight || 0
        const toolbarH = document.querySelector('.menu-toolbar')?.offsetHeight || 0
        const footerH = document.querySelector('.fixed-footer')?.offsetHeight || 0
        // Guard against transient 0s (element not yet laid out) clobbering a
        // good value — keep the CSS fallback in that case.
        if (topbarH) write('topbar', '--topbar-h', topbarH)
        if (topbarH) write('stack', '--stack-h', topbarH + toolbarH)
        if (footerH) write('footer', '--footer-h', footerH)
    }

    // Coalesce bursts — a ResizeObserver firing for all three elements, or a
    // resize/orientation change, should produce one measurement at frame time,
    // not one per notification.
    let frame = null
    function scheduleMeasure() {
        if (frame !== null) return
        frame = requestAnimationFrame(() => { frame = null; measure() })
    }

    function sync() {
        measure()
        if (!ro) return
        for (const sel of SELECTORS) {
            const el = document.querySelector(sel)
            if (el && !observed.has(el)) { ro.observe(el); observed.add(el) }
        }
    }

    let stopWatch = null
    onMounted(() => {
        ro = new ResizeObserver(scheduleMeasure)
        // Re-find and re-observe after each relevant reactive change, on the
        // next frame so the new DOM is laid out before we measure it.
        stopWatch = watch(ready, () => requestAnimationFrame(sync), { immediate: true })
        window.addEventListener('resize', scheduleMeasure, { passive: true })
        window.addEventListener('orientationchange', scheduleMeasure)
    })

    onUnmounted(() => {
        stopWatch?.()
        ro?.disconnect()
        ro = null
        if (frame !== null) cancelAnimationFrame(frame)
        window.removeEventListener('resize', scheduleMeasure)
        window.removeEventListener('orientationchange', scheduleMeasure)
    })
}
