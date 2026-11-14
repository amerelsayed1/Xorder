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
            <button class="btn btn-ghost btn-sm" style="min-height:40px" @click="addProof">{{ t('landing_admin.add') }}</button>
        </template>
        <p v-if="!content.proof.length" class="set-empty">{{ t('landing_admin.no_proof') }}</p>
        <div v-else class="space-y-3">
            <div v-for="(p, i) in content.proof" :key="i" class="set-item">
                <div class="set-item-head">
                    <span class="set-item-tag">{{ i + 1 }}</span>
                    <div class="set-item-actions">
                        <button class="icon-btn" :disabled="i === 0" :aria-label="t('landing_admin.move_up')" @click="move(content.proof, i, -1)"><i class="pi pi-arrow-up" aria-hidden="true" /></button>
                        <button class="icon-btn" :disabled="i === content.proof.length - 1" :aria-label="t('landing_admin.move_down')" @click="move(content.proof, i, 1)"><i class="pi pi-arrow-down" aria-hidden="true" /></button>
                        <button class="icon-btn icon-btn-danger" :aria-label="t('landing_admin.remove')" @click="removeAt(content.proof, i)"><i class="pi pi-trash" aria-hidden="true" /></button>
                    </div>
                </div>
                <div class="set-group">
                    <BiField :label="t('landing_admin.l_title')" v-model:en="p.title.en" v-model:ar="p.title.ar" />
                    <BiField :label="t('landing_admin.l_text')" v-model:en="p.text.en" v-model:ar="p.text.ar" />
                </div>
            </div>
        </div>
    </AdminSection>
</template>
