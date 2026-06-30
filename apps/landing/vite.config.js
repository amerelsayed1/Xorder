import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Standalone marketing/landing site. Content is fetched at runtime from the
// public API. In dev, leave VITE_API_URL unset so /api is proxied to Laravel.
const API_TARGET = process.env.VITE_API_URL || 'http://localhost:8000'

export default defineConfig({
    plugins: [vue(), tailwindcss()],
    server: {
        port: 5174,
        proxy: {
            '/api': { target: API_TARGET, changeOrigin: true },
            // So the "View Live Menu Demo" link (/r/{slug}) resolves in dev too.
            '/r': { target: API_TARGET, changeOrigin: true },
        },
    },
})
