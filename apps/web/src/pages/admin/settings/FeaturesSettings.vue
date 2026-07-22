<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addFeature, addIndustry } = useLandingContent()
</script>

<template>
    <!-- FEATURES -->
    <AdminSection :title="t('landing_admin.sec_features')" open>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.features.title.en" v-model:ar="content.features.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" textarea v-model:en="content.features.sub.en" v-model:ar="content.features.sub.ar" />
        </div>
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.feature_cards') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addFeature">{{ t('landing_admin.add_card') }}</button>
        </div>
        <div class="space-y-3">
            <div v-for="(f, i) in content.features.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2 gap-2">
                    <div class="flex items-center gap-2">
                        <span class="label">{{ t('landing_admin.icon') }}</span>
                        <input v-model="f.icon" class="input" style="width: 64px; text-align: center;" maxlength="4" />
                    </div>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.features.items, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.features.items.length - 1" @click="move(content.features.items, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.features.items, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_title')" v-model:en="f.title.en" v-model:ar="f.title.ar" />
                <BiField :label="t('landing_admin.l_text')" class="mt-2" textarea v-model:en="f.text.en" v-model:ar="f.text.ar" />
            </div>
        </div>
    </AdminSection>

    <!-- INDUSTRIES -->
    <AdminSection :title="t('landing_admin.sec_industries')" open>
        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.industries.title.en" v-model:ar="content.industries.title.ar" />
        <BiField :label="t('landing_admin.l_section_subtitle')" class="mt-2" v-model:en="content.industries.sub.en" v-model:ar="content.industries.sub.ar" />
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.industries') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addIndustry">{{ t('landing_admin.add') }}</button>
        </div>
        <div class="space-y-3">
            <div v-for="(it, i) in content.industries.items" :key="i" class="flex items-start gap-2">
                <input v-model="it.icon" class="input mt-1" style="width:56px;text-align:center" maxlength="4" />
                <BiField class="flex-1" v-model:en="it.text.en" v-model:ar="it.text.ar" />
                <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(content.industries.items, i)">✕</button>
            </div>
        </div>
    </AdminSection>
</template>
