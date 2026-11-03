<script setup>
// Team shell: staff and roles. They are built from the settings card
// primitives (settings.css), so they need those styles, but not the settings
// sub-menu — the sidebar's Team section already lists both pages. The
// breadcrumb comes from this route's `meta.crumbKey` (see SettingsHeader).
import { RouterView } from 'vue-router'
import './settings.css'
</script>

<template>
    <div class="set-main">
        <RouterView />
    </div>
</template>
