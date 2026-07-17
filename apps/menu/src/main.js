import { createApp } from 'vue'
import App from './App.vue'
import './app.css'

const app = createApp(App)

// Fade images in once decoded so cards never flash a blank box. Handles the
// cached case (image already complete before the listener attaches) and the
// error case (don't leave a broken image stuck invisible).
app.directive('img-fade', {
    mounted(el) {
        const reveal = () => el.classList.add('is-loaded')
        if (el.complete && el.naturalWidth > 0) reveal()
        else {
            el.addEventListener('load', reveal, { once: true })
            el.addEventListener('error', reveal, { once: true })
        }
    },
})

app.mount('#app')
