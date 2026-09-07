<script setup>
// Settings shell. One screen hosts every settings section; the persistent
// sub-menu on the inline-end edge switches between them, and the URL — not
// local state — decides which one is showing, so a section stays linkable and
// the back button works.
//
// Which sections appear is decided by `settings.config.js`, the same schema the
// main sidebar consults before it offers the Settings entry at all.
import { computed } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuth } from '@xorder/api-client/auth.js'
import { buildSettingsNav } from './settings.config.js'
import './settings.css'

const { t } = useI18n()
const auth = useAuth()
const route = useRoute()

const groups = computed(() => buildSettingsNav({
    features: auth.restaurant?.features || [],
    can: auth.can,
}))

// The staff/role create + edit forms are children of this shell too, so the
// sub-menu highlights by route-name prefix rather than exact match — editing a
// role should not leave the sub-menu looking like nothing is selected.
const isActive = (item) => route.name === item.to.name || String(route.name || '').startsWith(item.to.name + '.')
</script>

<template>
    <div class="set-shell">
        <main class="set-main">
            <RouterView />
        </main>

        <aside class="set-aside" :aria-label="t('settings_shell.title')">
            <div v-for="g in groups" :key="g.key" class="set-nav-group">
                <span class="set-nav-title">{{ t(g.labelKey) }}</span>
                <RouterLink
                    v-for="item in g.items"
                    :key="item.key"
                    :to="item.to"
                    class="set-nav-item"
                    :class="{ active: isActive(item) }"
                    :aria-current="isActive(item) ? 'page' : undefined"
                >
                    <span v-if="isActive(item)" class="set-nav-dot" aria-hidden="true"></span>
                    <span class="set-nav-label">{{ t(item.labelKey) }}</span>
                    <i :class="[item.icon, 'set-nav-ico']" aria-hidden="true"></i>
                </RouterLink>
            </div>
        </aside>
    </div>
</template>
