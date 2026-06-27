import { createApp } from 'vue'
import { createPinia } from 'pinia'
import router from './router'
import { i18n, setLocale } from './i18n'
import App from './App.vue'

setLocale(localStorage.getItem('locale') || 'en')

createApp(App)
    .use(createPinia())
    .use(router)
    .use(i18n)
    .mount('#app')
