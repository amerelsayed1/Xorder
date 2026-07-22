<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content } = useLandingContent()
</script>

<template>
    <!-- LEAD FORM -->
    <AdminSection :title="t('landing_admin.sec_lead_form')" open>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.lead_form.title.en" v-model:ar="content.lead_form.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.lead_form.sub.en" v-model:ar="content.lead_form.sub.ar" />
            <BiField :label="t('landing_admin.l_button')" v-model:en="content.lead_form.button.en" v-model:ar="content.lead_form.button.ar" />
            <BiField :label="t('landing_admin.l_success')" textarea v-model:en="content.lead_form.success.en" v-model:ar="content.lead_form.success.ar" />
        </div>
        <p class="page-sub mt-3" style="font-size:12px">{{ t('landing_admin.leads_hint') }}</p>
    </AdminSection>

    <!-- CTA -->
    <AdminSection :title="t('landing_admin.sec_cta')" open>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_title')" v-model:en="content.cta.title.en" v-model:ar="content.cta.title.ar" />
            <BiField :label="t('landing_admin.l_subtitle')" textarea v-model:en="content.cta.sub.en" v-model:ar="content.cta.sub.ar" />
            <BiField :label="t('landing_admin.l_button')" v-model:en="content.cta.button.en" v-model:ar="content.cta.button.ar" />
            <BiField :label="t('landing_admin.l_whatsapp_label')" v-model:en="content.cta.whatsapp_label.en" v-model:ar="content.cta.whatsapp_label.ar" />
        </div>
        <label class="block mt-4">
            <span class="label">{{ t('landing_admin.contact_email') }}</span>
            <input v-model="content.contact.email" class="input mt-1.5" type="email" placeholder="hello@xorder.app" />
        </label>
    </AdminSection>

    <!-- FOOTER -->
    <AdminSection :title="t('landing_admin.sec_footer')" open>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_tagline')" v-model:en="content.footer.tagline.en" v-model:ar="content.footer.tagline.ar" />
            <BiField :label="t('landing_admin.l_rights')" v-model:en="content.footer.rights.en" v-model:ar="content.footer.rights.ar" />
        </div>
    </AdminSection>
</template>
