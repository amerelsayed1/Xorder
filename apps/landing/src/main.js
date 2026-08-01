import { createApp } from 'vue'
import { i18n, setLocale } from '@xorder/ui/i18n'
import { installEnDigits } from '@xorder/ui/enDigits.js'
import { initAnalytics } from '@xorder/analytics'
import './app.css'
import LandingView from './LandingView.vue'

setLocale(localStorage.getItem('locale') || 'ar')

// Normalize Arabic-Indic / Persian digits to ASCII in phone & money inputs.
installEnDigits()

// Firebase Analytics (GA4). The landing page is a single view, so GA4's
// automatic page_view is enough; the `track()` calls in LandingView report the
// conversion events on top of that.
initAnalytics('landing')

createApp(LandingView).use(i18n).mount('#app')
