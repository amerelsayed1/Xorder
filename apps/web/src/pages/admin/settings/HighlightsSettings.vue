<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
// Only the proof points are still rendered by the landing hero. The old
// offer / problem / no-commission sections were removed from the landing, so
// their editors are dropped here (their data stays in the API as fallback).
const { content, move, removeAt, addProof } = useLandingContent()
</script>

<template>
    <!-- PROOF POINTS (hero highlights) -->
    <AdminSection :title="t('landing_admin.sec_proof')" :collapsible="false">
        <template #actions>
            <button class="btn btn-ghost btn-sm" @click="addProof">{{ t('landing_admin.add') }}</button>
        </template>
        <div class="space-y-3">
            <div v-for="(p, i) in content.proof" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2">
                    <span class="label">#{{ i + 1 }}</span>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.proof, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.proof.length - 1" @click="move(content.proof, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.proof, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_title')" v-model:en="p.title.en" v-model:ar="p.title.ar" />
                <BiField :label="t('landing_admin.l_text')" class="mt-2" v-model:en="p.text.en" v-model:ar="p.text.ar" />
            </div>
        </div>
    </AdminSection>
</template>
