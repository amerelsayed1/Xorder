import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// Keep the menu dev server aligned with the landing/dashboard proxies and the
// one-command local development script. Docker builds are static and do not
// use this development-only proxy.
const API_TARGET = process.env.VITE_API_URL || 'http://127.0.0.1:8100'

/**
 * Inline the entry stylesheet into index.html instead of linking it.
 *
 * The menu is a QR target: almost every load is a cold first visit on mobile
 * data, and the <link> Vite injects is render-blocking — it held back even the
 * inline boot splash for a full round-trip (~390 ms in the field). The sheet
 * gzips to ~13 KB, which rides inside the (also gzipped) HTML for far less
 * than the round-trip it replaces. The trade is repeat visits, which lose the
 * immutable cache hit on the stylesheet; a diner scanning a QR code rarely has
 * one, and the JS bundle they do re-fetch is cached either way.
 *
 * Only stylesheets the HTML actually links are inlined — CSS belonging to
 * async chunks is fetched by the chunk loader and must stay on disk.
 */
function inlineEntryCss() {
    return {
        name: 'xorder-inline-entry-css',
        apply: 'build',
        enforce: 'post',
        generateBundle(_options, bundle) {
            const html = bundle['index.html']
            if (!html || typeof html.source !== 'string') {
                return
            }

            for (const [key, asset] of Object.entries(bundle)) {
                if (asset.type !== 'asset' || !asset.fileName.endsWith('.css')) {
                    continue
                }

                const escaped = asset.fileName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                const link = new RegExp(`<link[^>]+href="[^"]*${escaped}"[^>]*>`)
                if (!link.test(html.source)) {
                    continue
                }

                html.source = html.source.replace(link, `<style>${asset.source}</style>`)
                delete bundle[key]
            }
        },
    }
}

export default defineConfig({
    base: '/menu/',
    plugins: [vue(), tailwindcss(), inlineEntryCss()],
    server: {
        port: 5175,
        proxy: {
            '/api': { target: API_TARGET, changeOrigin: true },
        },
    },
})
