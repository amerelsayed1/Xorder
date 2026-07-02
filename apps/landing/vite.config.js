import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Standalone marketing/landing site. Content is fetched at runtime from the
// public API. In dev, leave VITE_API_URL unset so /api is proxied to Laravel.
// Use 127.0.0.1 (not localhost) so the dev proxy hits the IPv4 Laravel server
// and isn't shadowed by anything bound to IPv6 ::1:8000 (e.g. a Docker stack).
const API_TARGET = process.env.VITE_API_URL || 'http://127.0.0.1:8100'

export default defineConfig({
    plugins: [vue(), tailwindcss()],
    server: {
        port: 5174,
        proxy: {
            '/api': { target: API_TARGET, changeOrigin: true },
            // So the "View Live Menu Demo" link (/r/{slug}) resolves in dev too.
            // Anchored regex so it only matches /r/… and not other paths.
            '^/r/': { target: API_TARGET, changeOrigin: true },
        },
    },
})
