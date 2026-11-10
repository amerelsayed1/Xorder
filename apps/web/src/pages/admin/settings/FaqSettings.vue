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
        <div class="set-group">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.faq.title.en" v-model:ar="content.faq.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.faq.sub.en" v-model:ar="content.faq.sub.ar" />
        </div>

        <div class="set-sub-head">
            <div class="min-w-0">
                <h3 class="h-card" style="font-size:15px">{{ t('landing_admin.faq') }}</h3>
                <p class="set-help mt-1">{{ t('landing_admin.faq_hint') }}</p>
            </div>
            <button class="btn btn-ghost btn-sm" @click="addFaq">{{ t('landing_admin.add_faq') }}</button>
        </div>

        <p v-if="!content.faq.items.length" class="set-empty">{{ t('landing_admin.empty_items') }}</p>
        <div v-else class="space-y-4">
            <div v-for="(item, i) in content.faq.items" :key="i" class="set-item">
                <div class="set-item-head flex-wrap">
                    <label class="set-check" style="min-height:44px">
                        <input type="checkbox" v-model="item.enabled" /> {{ t('landing_admin.visible') }}
                    </label>
                    <div class="set-item-actions">
                        <button class="icon-btn" :disabled="i === 0" :aria-label="t('landing_admin.move_up')" @click="move(content.faq.items, i, -1)"><i class="pi pi-arrow-up" aria-hidden="true" /></button>
                        <button class="icon-btn" :disabled="i === content.faq.items.length - 1" :aria-label="t('landing_admin.move_down')" @click="move(content.faq.items, i, 1)"><i class="pi pi-arrow-down" aria-hidden="true" /></button>
                        <button class="icon-btn icon-btn-danger" :aria-label="t('landing_admin.remove')" @click="removeAt(content.faq.items, i)"><i class="pi pi-trash" aria-hidden="true" /></button>
                    </div>
                </div>
                <div class="set-group">
                    <BiField :label="t('landing_admin.l_faq_question')" v-model:en="item.q.en" v-model:ar="item.q.ar" />
                    <BiField :label="t('landing_admin.l_faq_answer')" textarea v-model:en="item.a.en" v-model:ar="item.a.ar" />
                </div>
            </div>
        </div>
    </AdminSection>
</template>
