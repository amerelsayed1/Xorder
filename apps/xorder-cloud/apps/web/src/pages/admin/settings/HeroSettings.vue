<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content } = useLandingContent()
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_hero')" open>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_badge')" v-model:en="content.hero.badge.en" v-model:ar="content.hero.badge.ar" />
            <BiField :label="t('landing_admin.l_title')" v-model:en="content.hero.title.en" v-model:ar="content.hero.title.ar" />
            <BiField :label="t('landing_admin.l_subtitle')" textarea v-model:en="content.hero.sub.en" v-model:ar="content.hero.sub.ar" />
        </div>
        <!-- Each button: its bilingual label, then its (single) link under the first column -->
        <div class="set-group">
            <BiField :label="t('landing_admin.l_primary_button')" v-model:en="content.hero.cta.en" v-model:ar="content.hero.cta.ar" />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label class="block"><span class="label">{{ t('landing_admin.l_primary_link') }}</span>
                    <input v-model="content.hero.primary_link" class="input mt-1.5" placeholder="#lead" dir="ltr" /></label>
            </div>
        </div>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_secondary_button')" v-model:en="content.hero.secondary.en" v-model:ar="content.hero.secondary.ar" />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label class="block"><span class="label">{{ t('landing_admin.l_secondary_link') }}</span>
                    <input v-model="content.hero.secondary_link" class="input mt-1.5" :placeholder="t('landing_admin.demo_link_ph')" dir="ltr" /></label>
            </div>
        </div>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_no_commission_label')" v-model:en="content.hero.no_commission_label.en" v-model:ar="content.hero.no_commission_label.ar" />
            <BiField :label="t('landing_admin.l_ready_label')" v-model:en="content.hero.ready_label.en" v-model:ar="content.hero.ready_label.ar" />
            <BiField :label="t('landing_admin.l_whatsapp_label')" v-model:en="content.hero.whatsapp_label.en" v-model:ar="content.hero.whatsapp_label.ar" />
        </div>
    </AdminSection>
</template>
