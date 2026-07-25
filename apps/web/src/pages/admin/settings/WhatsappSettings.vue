<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'
import { isValidMobile } from '../../../lib/phone.js'

const { t } = useI18n()
const { content } = useLandingContent()

// Immediate hint; the server re-validates this field on Save.
const numberInvalid = computed(() => !isValidMobile(content.value?.whatsapp?.number))
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_whatsapp')" open>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="block"><span class="label">{{ t('landing_admin.wa_number') }}</span>
                <input v-model="content.whatsapp.number" class="input mt-1.5" placeholder="201234567890" dir="ltr" :aria-invalid="numberInvalid" />
                <span v-if="numberInvalid" class="block text-xs mt-1" style="color:var(--red,#b42318)">{{ t('restaurant.phone_invalid') }}</span></label>
        </div>
        <BiField class="mt-3" :label="t('landing_admin.wa_message')" textarea v-model:en="content.whatsapp.default_message.en" v-model:ar="content.whatsapp.default_message.ar" />
        <div class="flex flex-wrap gap-5 mt-3">
            <label class="flex items-center gap-2 label" style="cursor:pointer">
                <input type="checkbox" v-model="content.whatsapp.floating_enabled" /> {{ t('landing_admin.wa_floating') }}
            </label>
            <label class="flex items-center gap-2 label" style="cursor:pointer">
                <input type="checkbox" v-model="content.whatsapp.hero_enabled" /> {{ t('landing_admin.wa_hero') }}
            </label>
        </div>
    </AdminSection>
</template>
