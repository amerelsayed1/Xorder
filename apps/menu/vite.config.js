import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Public guest menu SPA, served at /menu on each restaurant subdomain.
const API_TARGET = process.env.VITE_API_URL || 'http://localhost:8000'

export default defineConfig({
    base: '/menu/',
    plugins: [vue(), tailwindcss()],
    server: {
        port: 5175,
        proxy: {
            '/api': { target: API_TARGET, changeOrigin: true },
        },
    },
})
