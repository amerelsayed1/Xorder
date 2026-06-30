import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import tailwindcss from '@tailwindcss/vite';

// FULLY DECOUPLED build. This API serves only the server-rendered public menu
// (Blade), so its Vite build compiles ONLY the public-menu stylesheet.
//
// The SPA (apps/web) and landing (apps/landing) are standalone Vite apps that
// build and deploy independently and talk to this API over HTTP. Do NOT add
// ../web or ../landing inputs here — that re-couples the frontend to Laravel.
export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/public.css'],
            refresh: ['resources/views/**/*.blade.php'],
        }),
        tailwindcss(),
    ],
    server: {
        watch: {
            ignored: ['**/storage/framework/views/**'],
        },
    },
});
