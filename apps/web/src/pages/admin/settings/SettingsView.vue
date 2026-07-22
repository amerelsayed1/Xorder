<script setup>
import { onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, loading, saving, errorList, savedFlash, load, save } = useLandingContent()

onMounted(load)
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
                    <button class="btn btn-accent" :disabled="saving || loading" @click="save">
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

            <div v-if="loading" class="card mt-5 p-8 text-center page-sub">{{ t('common.loading') }}</div>

            <!-- Active settings sub-page. Mounts only once the document is loaded
                 so children can bind to `content` without null guards. -->
            <template v-else-if="content">
                <RouterView />

                <!-- Save bar -->
                <div class="flex justify-end mt-6 pb-10">
                    <button class="btn btn-accent" :disabled="saving" @click="save">
                        {{ saving ? t('common.saving') : t('admin.save_changes') }}
                    </button>
                </div>
            </template>
        </div>
    </div>
</template>
