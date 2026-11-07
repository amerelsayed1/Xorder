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
    <div class="nf">
        <div class="card nf-card">
            <div class="nf-code" aria-hidden="true">404</div>
            <h1 class="page-title mt-2">{{ t('common.nf_title') }}</h1>
            <p class="page-sub mt-2" style="color:var(--body)">{{ t('common.nf_message') }}</p>
            <div class="flex items-center justify-center gap-3 flex-wrap mt-7">
                <button class="btn btn-accent nf-btn" @click="goHome">{{ t('common.nf_dashboard') }}</button>
                <button class="btn btn-ghost nf-btn" @click="goBack">{{ t('common.nf_back') }}</button>
            </div>
        </div>
    </div>
</template>

<style scoped>
.nf { min-height: 60vh; display: flex; align-items: center; justify-content: center; padding: 24px 0; }
.nf-card { width: 100%; max-width: 460px; padding: 40px 28px; text-align: center; }
.nf-code { font-family: var(--font-display); font-weight: 700; line-height: 1; font-size: clamp(72px, 16vw, 112px); color: var(--accent); }
.nf-btn { min-height: 44px; justify-content: center; }
</style>
