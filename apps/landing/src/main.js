import { createApp } from 'vue'
import { i18n, setLocale } from '@xorder/ui/i18n'
import { installEnDigits } from '@xorder/ui/enDigits.js'
import { initAnalytics, initPerformance } from '@xorder/analytics'
import './app.css'
import LandingView from './LandingView.vue'

setLocale(localStorage.getItem('locale') || 'ar')

// Normalize Arabic-Indic / Persian digits to ASCII in phone & money inputs.
installEnDigits()

// Firebase Analytics (GA4) + Performance Monitoring. The landing page is a
// single view, so GA4's automatic page_view is enough; the `track()` calls in
// LandingView report the conversion events on top of that. Performance adds the
// page-load trace — the number that decides whether a visitor waits or leaves.
//
// Started after mount at an idle moment — this is the marketing front door, so
// the SDK must never delay first paint.
createApp(LandingView).use(i18n).mount('#app')

const startAnalytics = () => {
    initAnalytics('landing')
    initPerformance()
}
if ('requestIdleCallback' in window) requestIdleCallback(startAnalytics, { timeout: 3000 })
else setTimeout(startAnalytics, 1000)
