<script setup>
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'

const { t } = useI18n()
const router = useRouter()

function goHome() {
    router.push({ name: 'admin.dashboard' })
}
function goBack() {
    // Fall back to the dashboard if there is no in-app history to go back to.
    if (window.history.length > 1) router.back()
    else goHome()
}
</script>

<template>
    <div class="portal theme-indigo">
        <div class="min-h-[70vh] flex items-center justify-center px-5 py-16">
            <div class="text-center max-w-md">
                <div class="font-bold leading-none" style="font-size: clamp(72px, 16vw, 120px); color: var(--accent);">404</div>
                <h1 class="page-title mt-3">{{ t('common.nf_title') }}</h1>
                <p class="page-sub mt-2">{{ t('common.nf_message') }}</p>
                <div class="flex items-center justify-center gap-3 flex-wrap mt-7">
                    <button class="btn btn-accent" @click="goHome">{{ t('common.nf_dashboard') }}</button>
                    <button class="btn btn-ghost" @click="goBack">{{ t('common.nf_back') }}</button>
                </div>
            </div>
        </div>
    </div>
</template>
