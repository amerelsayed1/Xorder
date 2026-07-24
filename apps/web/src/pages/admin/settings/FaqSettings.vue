<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addFaq } = useLandingContent()
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_faq')" :collapsible="false">
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.faq.title.en" v-model:ar="content.faq.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.faq.sub.en" v-model:ar="content.faq.sub.ar" />
        </div>

        <p class="text-sm mt-4" style="color: var(--muted);">{{ t('landing_admin.faq_hint') }}</p>

        <div class="flex items-center justify-between mt-3 mb-3">
            <span class="label">{{ t('landing_admin.faq') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addFaq">{{ t('landing_admin.add_faq') }}</button>
        </div>

        <div class="space-y-4">
            <div v-for="(item, i) in content.faq.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2 gap-3 flex-wrap">
                    <label class="flex items-center gap-2 label" style="cursor: pointer;">
                        <input type="checkbox" v-model="item.enabled" /> {{ t('landing_admin.visible') }}
                    </label>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.faq.items, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.faq.items.length - 1" @click="move(content.faq.items, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.faq.items, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_faq_question')" v-model:en="item.q.en" v-model:ar="item.q.ar" />
                <BiField :label="t('landing_admin.l_faq_answer')" class="mt-2" textarea v-model:en="item.a.en" v-model:ar="item.a.ar" />
            </div>
        </div>
    </AdminSection>
</template>
