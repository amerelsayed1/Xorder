import { defineConfig } from 'vitest/config'

// One runner for every Vue app and shared package: `pnpm test`.
// Tests sit beside the code as *.test.js. jsdom gives the few modules that
// read window.location / localStorage a browser-shaped global.
export default defineConfig({
    test: {
        environment: 'jsdom',
        include: ['apps/*/src/**/*.test.js', 'packages/*/src/**/*.test.js'],
    },
})
