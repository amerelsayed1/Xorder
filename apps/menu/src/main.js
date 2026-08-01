import { createApp } from 'vue'
import { installEnDigits } from '@xorder/ui/enDigits.js'
import { initAnalytics } from '@xorder/analytics'
import App from './App.vue'
import './app.css'

// Firebase Analytics (GA4). No-op until /firebase-config.js carries a
// measurementId. The firebase SDK is lazy-loaded so it stays out of the
// menu's initial bundle.
initAnalytics('menu')

// Normalize Arabic-Indic / Persian digits to ASCII in phone & money inputs.
installEnDigits()

const app = createApp(App)

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
