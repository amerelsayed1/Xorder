<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addIndustry } = useLandingContent()
</script>

<template>
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
                <div class="flex gap-1 mt-1">
                    <button class="icon-btn" :disabled="i === 0" @click="move(content.industries.items, i, -1)">↑</button>
                    <button class="icon-btn" :disabled="i === content.industries.items.length - 1" @click="move(content.industries.items, i, 1)">↓</button>
                    <button class="icon-btn icon-btn-danger" @click="removeAt(content.industries.items, i)">✕</button>
                </div>
            </div>
        </div>
    </AdminSection>
</template>
