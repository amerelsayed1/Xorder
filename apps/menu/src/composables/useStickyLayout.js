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

    function measure() {
        const topbarH = document.querySelector('.topbar')?.offsetHeight || 0
        const toolbarH = document.querySelector('.menu-toolbar')?.offsetHeight || 0
        const footerH = document.querySelector('.fixed-footer')?.offsetHeight || 0
        // Guard against transient 0s (element not yet laid out) clobbering a
        // good value — keep the CSS fallback in that case.
        if (topbarH) root.style.setProperty('--topbar-h', `${topbarH}px`)
        if (topbarH) root.style.setProperty('--stack-h', `${topbarH + toolbarH}px`)
        if (footerH) root.style.setProperty('--footer-h', `${footerH}px`)
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
        ro = new ResizeObserver(measure)
        // Re-find and re-observe after each relevant reactive change, on the
        // next frame so the new DOM is laid out before we measure it.
        stopWatch = watch(ready, () => requestAnimationFrame(sync), { immediate: true })
        window.addEventListener('resize', measure, { passive: true })
        window.addEventListener('orientationchange', measure)
    })

    onUnmounted(() => {
        stopWatch?.()
        ro?.disconnect()
        ro = null
        window.removeEventListener('resize', measure)
        window.removeEventListener('orientationchange', measure)
    })
}
