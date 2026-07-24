<script setup>
import { onMounted, onBeforeUnmount } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'
import { useI18n } from 'vue-i18n'
import Skeleton from '@xorder/ui/Skeleton.vue'
import { confirm } from '@xorder/ui/confirm.js'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, loading, saving, errorList, savedFlash, isDirty, load, save } = useLandingContent()

// Preview opens the public landing app. Set VITE_LANDING_URL for production;
// in dev it defaults to the landing dev server (see apps/landing package.json).
const previewUrl = import.meta.env.VITE_LANDING_URL || (import.meta.env.DEV ? 'http://localhost:5174' : '')

// Save-direct model: publishing is immediate, so confirm before it goes live.
async function confirmAndSave() {
    const ok = await confirm({
        title: t('landing_admin.save_confirm_title'),
        message: t('landing_admin.save_confirm_body'),
        confirmText: t('landing_admin.save_confirm_ok'),
    })
    if (ok) await save()
}

// Warn before losing unsaved edits — on in-app navigation and on tab close.
onBeforeRouteLeave(() => {
    if (isDirty.value && !window.confirm(t('landing_admin.unsaved_warning'))) return false
})
function onBeforeUnload(e) {
    if (isDirty.value) { e.preventDefault(); e.returnValue = '' }
}
onMounted(() => {
    load()
    window.addEventListener('beforeunload', onBeforeUnload)
})
onBeforeUnmount(() => window.removeEventListener('beforeunload', onBeforeUnload))
</script>

<template>
    <div class="portal theme-indigo">
        <div class="max-w-4xl mx-auto px-5 py-7">
            <!-- Header (shared across every settings sub-page) -->
            <div class="flex items-center justify-between gap-4 flex-wrap">
                <div>
                    <h1 class="page-title">{{ t('settings_admin.title') }}</h1>
                    <p class="page-sub">{{ t('settings_admin.subtitle') }}</p>
                </div>
                <div class="flex items-center gap-3">
                    <span v-if="savedFlash" class="badge badge-green"><span class="dot"></span> {{ t('common.saved') }}</span>
                    <span v-else-if="isDirty" class="badge"><span class="dot"></span> {{ t('common.unsaved_changes') }}</span>
                    <a v-if="previewUrl" :href="previewUrl" target="_blank" rel="noopener" class="btn btn-ghost">
                        {{ t('landing_admin.preview_site') }}
                    </a>
                    <button class="btn btn-accent" :disabled="saving || loading" @click="confirmAndSave">
                        {{ saving ? t('common.saving') : t('admin.save_changes') }}
                    </button>
                </div>
            </div>

            <!-- Errors -->
            <div v-if="errorList.length" class="card mt-5 p-4" style="border-color: var(--red); background: var(--red-soft);">
                <p class="font-semibold mb-1" style="color: var(--red);">{{ t('landing_admin.fix_errors') }}</p>
                <ul class="list-disc ps-5 text-sm" style="color: var(--red);">
                    <li v-for="(msg, i) in errorList" :key="i">{{ msg }}</li>
                </ul>
            </div>

            <div v-if="loading" class="card mt-5 p-6 space-y-5">
                <div v-for="n in 3" :key="n" class="space-y-2.5">
                    <Skeleton w="30%" h="13px" />
                    <Skeleton w="100%" h="40px" rounded="10px" />
                </div>
            </div>

            <!-- Active settings sub-page. Mounts only once the document is loaded
                 so children can bind to `content` without null guards. -->
            <template v-else-if="content">
                <RouterView />
                <!-- Single Save action lives in the header above; no duplicate bottom bar. -->
                <div class="pb-10"></div>
            </template>
        </div>
    </div>
</template>
