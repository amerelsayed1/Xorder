import { createApp } from 'vue'
import { i18n, setLocale } from '@xorder/ui/i18n'
import './app.css'
import LandingView from './LandingView.vue'

setLocale(localStorage.getItem('locale') || 'ar')

createApp(LandingView).use(i18n).mount('#app')
