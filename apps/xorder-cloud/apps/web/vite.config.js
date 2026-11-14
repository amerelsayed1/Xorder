import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Standalone SPA (super-admin + restaurant dashboard). Talks to the Laravel
// API over HTTP. In dev, leave VITE_API_URL unset so requests stay same-origin
// and are proxied to the API below (keeps Sanctum cookies working without CORS).
// In prod, set VITE_API_URL to the API origin (e.g. https://api.tryorder.net).
// Use 127.0.0.1 (not localhost) so the dev proxy hits the IPv4 Laravel server
// and isn't shadowed by anything bound to IPv6 ::1:8000 (e.g. a Docker stack).
const API_TARGET = process.env.VITE_API_URL || 'http://127.0.0.1:8100'

export default defineConfig({
    // Served at the root of each admin subdomain (admin.* and {slug}.*).
    base: '/',
    plugins: [vue(), tailwindcss()],
    server: {
        port: 5173,
        proxy: {
            '/api': { target: API_TARGET, changeOrigin: true },
            '/sanctum': { target: API_TARGET, changeOrigin: true },
            // Public menu / QR preview links (/r/{slug}) resolve in dev too.
            // Anchored regex so it only matches /r/… and not SPA routes like
            // /restaurants (which must fall through to Vite's history fallback).
            '^/r/': { target: API_TARGET, changeOrigin: true },
        },
    },
})
