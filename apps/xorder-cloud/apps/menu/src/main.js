import { createApp } from 'vue'
import { installEnDigits } from '@xorder/ui/enDigits.js'
import { initAnalytics } from '@xorder/analytics'
import App from './App.vue'
import './app.css'

// Firebase Analytics (GA4) only. No-op until /firebase-config.js carries a
// config. The firebase SDK is lazy-loaded so it stays out of the initial bundle.
//
// Firebase Performance Monitoring used to start here too, and no longer does.
// It cannot be configured out of an installations call and a
// firebaseremoteconfig `fireperf:fetch` before it will record anything (see the
// note on initPerformance) — in a field trace those were the last and slowest
// nodes of the load chain, ~2.5 s in. Monitoring the QR-scan page by making the
// QR-scan page slower is a bad trade. Origin-level field data for xorder.io
// still comes from CrUX, which costs the diner nothing.
//
// GA4 stays: menu_viewed -> menu_add_to_cart -> menu_order_submitted is the
// conversion funnel, and add-to-cart in particular exists nowhere else (an
// abandoned cart never reaches the API). It is expensive though — gtag.js is
// ~146 KiB transferred — so it is gated behind the load event plus the first
// idle slot, instead of a bare requestIdleCallback that can fire while the menu
// is still fetching. The gate lives inside initAnalytics so that the first
// track() call cannot pull the SDK in ahead of it; events raised meanwhile are
// held and sent when it opens, so no event is dropped.
function afterLoadAndIdle() {
    return new Promise((resolve) => {
        const idle = () =>
            'requestIdleCallback' in window
                ? requestIdleCallback(() => resolve(), { timeout: 1000 })
                : setTimeout(resolve, 200)

        if (document.readyState === 'complete') idle()
        else window.addEventListener('load', idle, { once: true })
    })
}

// Guest paging (docs/features/guest-paging, S3): a receipt QR opens
// /menu/o/{token}. That is not the menu: it is a small page that shows the
// diner their order number and its state. The menu bundle is already in this
// entry, but none of it runs for that path: no menu fetch, no cart, no
// analytics. The page itself is a separate chunk, loaded only for that path, so
// the menu's own first load is unchanged.
const trackMatch = /^\/menu\/o\/([A-Za-z0-9]{40})\/?$/.exec(window.location.pathname)
const TrackingApp = trackMatch ? (await import('./tracking/TrackingApp.vue')).default : null

// Guest paging, shared QR (docs/features/guest-paging-shared-qr): the restaurant's
// one standing QR opens /menu/p. Same idea as above: a small page that shows the
// client a short code to read out, then moves to their order-number page.
const joinMatch = /^\/menu\/p\/?$/.test(window.location.pathname)
const JoinApp = joinMatch ? (await import('./tracking/JoinApp.vue')).default : null

// Normalize Arabic-Indic / Persian digits to ASCII in phone & money inputs.
installEnDigits()

// Registered before mount so it is in place ahead of the first track() call.
if (!trackMatch && !joinMatch) initAnalytics('menu', { until: afterLoadAndIdle() })

const app = trackMatch
    ? createApp(TrackingApp, { token: trackMatch[1] })
    : joinMatch ? createApp(JoinApp) : createApp(App)

// Fade images in once decoded so cards never flash a blank box, and resolve the
// loading state on BOTH success and failure so a card never shimmers forever.
//
// The old version only revealed on `complete && naturalWidth > 0`. A cached
// image that had already *errored* before the directive mounted is `complete`
// with `naturalWidth === 0`, so it fell through to attach load/error listeners
// that never fire again — the endless "loading" placeholder. We now settle from
// `complete` alone (success or error), tag failures with `is-error` so the CSS
// can swap in a clean fallback, and re-run when the same <img> element is reused
// for a different `src` (the modal image, which persists across opens).
function settleFade(el, ok) {
    el.classList.add('is-loaded')
    el.classList.toggle('is-error', !ok)
}

function initFade(el) {
    el.classList.remove('is-loaded', 'is-error')
    el.dataset.fadeSrc = el.currentSrc || el.getAttribute('src') || ''
    if (el.complete) {
        settleFade(el, el.naturalWidth > 0)
    } else {
        el.addEventListener('load', () => settleFade(el, true), { once: true })
        el.addEventListener('error', () => settleFade(el, false), { once: true })
    }
}

app.directive('img-fade', {
    mounted: initFade,
    updated(el) {
        const now = el.currentSrc || el.getAttribute('src') || ''
        if (now !== el.dataset.fadeSrc) initFade(el)
    },
})

app.mount('#app')
