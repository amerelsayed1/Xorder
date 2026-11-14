<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content } = useLandingContent()
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_seo')" :collapsible="false">
        <div class="set-group">
            <BiField :label="t('landing_admin.seo_title')" v-model:en="content.seo.title.en" v-model:ar="content.seo.title.ar" />
            <BiField :label="t('landing_admin.seo_desc')" textarea v-model:en="content.seo.description.en" v-model:ar="content.seo.description.ar" />
        </div>
        <div class="set-group">
            <BiField :label="t('landing_admin.og_title')" v-model:en="content.seo.og_title.en" v-model:ar="content.seo.og_title.ar" />
            <BiField :label="t('landing_admin.og_desc')" textarea v-model:en="content.seo.og_description.en" v-model:ar="content.seo.og_description.ar" />
            <label class="block"><span class="label">{{ t('landing_admin.og_image') }}</span>
                <input v-model="content.seo.og_image" class="input mt-1.5" placeholder="https://…" maxlength="500" dir="ltr" /></label>
        </div>
    </AdminSection>
</template>
