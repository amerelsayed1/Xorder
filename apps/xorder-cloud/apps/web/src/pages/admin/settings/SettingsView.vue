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
        <div class="max-w-4xl mx-auto px-5 pb-7 settings-shell">
            <!-- Header (shared across every settings sub-page). Sticky so the one
                 Save action is always in reach on a long page. -->
            <div class="set-head">
                <div class="min-w-0">
                    <h1 class="page-title">{{ t('settings_admin.title') }}</h1>
                    <p class="page-sub set-sub" style="color:var(--body)">{{ t('settings_admin.subtitle') }}</p>
                </div>
                <div class="flex flex-wrap items-center gap-3">
                    <span aria-live="polite">
                        <span v-if="savedFlash" class="badge badge-green"><span class="dot"></span> {{ t('common.saved') }}</span>
                        <span v-else-if="isDirty" class="badge badge-amber"><span class="dot"></span> {{ t('common.unsaved_changes') }}</span>
                    </span>
                    <a v-if="previewUrl" :href="previewUrl" target="_blank" rel="noopener" class="btn btn-ghost set-btn">
                        <i class="pi pi-external-link" aria-hidden="true" />{{ t('landing_admin.preview_site') }}
                    </a>
                    <button class="btn btn-accent set-btn" :disabled="saving || loading" @click="confirmAndSave">
                        {{ saving ? t('common.saving') : t('admin.save_changes') }}
                    </button>
                </div>
            </div>

            <!-- Errors -->
            <div v-if="errorList.length" class="card mt-5 p-4" role="alert" style="border-color: var(--red); background: var(--red-soft);">
                <p class="font-semibold mb-1" style="color: var(--red);">{{ t('landing_admin.fix_errors') }}</p>
                <ul class="list-disc ps-5 text-sm" style="color: var(--red);">
                    <li v-for="(msg, i) in errorList" :key="i">{{ msg }}</li>
                </ul>
            </div>

            <!-- Loading: mirrors a section with bilingual field pairs -->
            <div v-if="loading" class="card mt-5 p-5 space-y-5">
                <Skeleton w="35%" h="20px" />
                <div v-for="n in 3" :key="n" class="space-y-2.5">
                    <Skeleton w="30%" h="13px" />
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <Skeleton w="100%" h="42px" rounded="10px" />
                        <Skeleton w="100%" h="42px" rounded="10px" />
                    </div>
                </div>
            </div>

            <!-- Active settings sub-page. Mounts only once the document is loaded
                 so children can bind to `content` without null guards. -->
            <template v-else-if="content">
                <!-- Every text field below comes as an EN / AR pair; this key says which is which -->
                <p class="lang-key" aria-hidden="true">
                    <span class="lang-tag">EN</span> English
                    <span class="lang-tag lang-tag-ar">AR</span> العربية
                </p>
                <div class="settings-body">
                    <RouterView />
                </div>
                <!-- Single Save action lives in the header above; no duplicate bottom bar. -->
                <div class="pb-10"></div>
            </template>
        </div>
    </div>
</template>

<style scoped>
/* Colours come from the shared theme variables and the PrimeVue primary scale. */
.settings-shell { padding-top: 0; }
.set-head { position: sticky; top: 64px; z-index: 20; display: flex; flex-wrap: wrap; align-items: center;
    justify-content: space-between; gap: 12px 16px; padding: 14px 20px; margin-inline: -20px;
    background: var(--page); border-bottom: 1px solid var(--line); }
.set-btn { min-height: 44px; }
.badge-amber { color: var(--p-primary-800); }

/* EN / AR key */
.lang-key { display: flex; align-items: center; gap: 8px; margin-top: 16px; font-size: 13.5px; color: var(--body); }
.lang-tag { display: inline-grid; place-items: center; min-width: 30px; height: 22px; padding: 0 6px; border-radius: 6px;
    background: var(--card); border: 1px solid var(--line); font-size: 11.5px; font-weight: 700; letter-spacing: .04em; color: var(--ink); }
.lang-tag-ar { background: var(--accent-soft); margin-inline-start: 10px; }

/* Shared look for every settings sub-page. They reach these through the
   .settings-body wrapper, so one rule here keeps all ten pages identical. */
.settings-body :deep(.admin-section) { margin-top: 16px; }
/* Arabic half of a bilingual pair: tinted, so the two read as one pair */
.settings-body :deep(.input[dir=rtl]) { background: var(--accent-soft); }
.settings-body :deep(textarea.input) { resize: vertical; min-height: 76px; line-height: 1.5; }
.settings-body :deep(.label) { display: block; }
.settings-body :deep(input[type=checkbox]) { width: 18px; height: 18px; flex: none; accent-color: var(--accent); }

/* Repeater cards: one per proof point, feature, step, question */
.settings-body :deep(.set-item) { background: var(--page); border: 1px solid var(--line); border-radius: 12px; padding: 14px; }
.settings-body :deep(.set-item-head) { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.settings-body :deep(.set-item-tag) { display: inline-grid; place-items: center; min-width: 28px; height: 28px; padding: 0 8px;
    border-radius: 8px; background: var(--card); border: 1px solid var(--line); font-size: 13px; font-weight: 700; color: var(--ink); }
.settings-body :deep(.set-item-actions) { display: flex; gap: 4px; margin-inline-start: auto; }
.settings-body :deep(.set-item .icon-btn) { width: 40px; height: 40px; color: var(--body); background: var(--card); border-color: var(--line); }
.settings-body :deep(.set-item .icon-btn:hover) { color: var(--ink); border-color: var(--muted); }
.settings-body :deep(.set-item .icon-btn-danger:hover) { color: var(--red); background: var(--red-soft); }
.settings-body :deep(.set-empty) { padding: 18px; border: 1px dashed var(--line); border-radius: 12px; text-align: center;
    font-size: 14px; color: var(--body); }
.settings-body :deep(.set-sub-head) { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px;
    margin-top: 24px; margin-bottom: 12px; padding-top: 20px; border-top: 1px solid var(--line); }
.settings-body :deep(.set-sub-head .btn) { min-height: 40px; }
.settings-body :deep(.set-help) { font-size: 13.5px; color: var(--body); }
/* Related fields grouped inside a section, separated by a hairline */
.settings-body :deep(.set-group) { display: flex; flex-direction: column; gap: 16px; }
.settings-body :deep(.set-group + .set-group) { margin-top: 24px; padding-top: 24px; border-top: 1px solid var(--line); }
.settings-body :deep(.set-check) { display: flex; align-items: center; gap: 10px; min-height: 48px; padding: 10px 14px; cursor: pointer;
    border: 1px solid var(--line); border-radius: 12px; background: var(--card); font-size: 14.5px; font-weight: 500; color: var(--ink); }
.settings-body :deep(.set-check:hover) { border-color: var(--muted); }
.settings-body :deep(.set-check:has(input:checked)) { border-color: var(--accent); background: var(--accent-soft); }
.settings-body :deep(.set-err) { display: block; margin-top: 6px; font-size: 13px; color: var(--red); }

@media (max-width: 640px) {
    .set-sub { display: none; }
    .set-head { padding-block: 10px; }
}
</style>
