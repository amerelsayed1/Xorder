import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Keep the menu dev server aligned with the landing/dashboard proxies and the
// one-command local development script. Docker builds are static and do not
// use this development-only proxy.
const API_TARGET = process.env.VITE_API_URL || 'http://127.0.0.1:8100'

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
