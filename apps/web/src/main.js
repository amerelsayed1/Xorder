import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import { definePreset } from '@primeuix/themes'
import Aura from '@primeuix/themes/aura'
import 'primeicons/primeicons.css'
import 'flowbite'
import './app.css'
import router from './router'
import { i18n, setLocale } from '@xorder/ui/i18n'
import { initAnalytics } from '@xorder/analytics'
import App from './App.vue'

// Firebase Analytics (GA4). No-op until /firebase-config.js carries a
// measurementId; page views are reported per-route from the router.
initAnalytics('web')

// Xorder-branded Aura preset: primary = brand orange (#f89a06).
const XorderAura = definePreset(Aura, {
    semantic: {
        primary: {
            50: '#fff8ec',
            100: '#feecc8',
            200: '#fdd88a',
            300: '#fbc44d',
            400: '#faab1f',
            500: '#f89a06',
            600: '#d9850a',
            700: '#b46a08',
            800: '#8f540f',
            900: '#764511',
            950: '#442304',
        },
    },
})

setLocale(localStorage.getItem('locale') || 'ar')

createApp(App)
    .use(createPinia())
    .use(router)
    .use(i18n)
    .use(PrimeVue, {
        theme: {
            preset: XorderAura,
            options: {
                darkModeSelector: '.app-dark',
                cssLayer: { name: 'primevue', order: 'theme, base, primevue' },
            },
        },
    })
    .mount('#app')
