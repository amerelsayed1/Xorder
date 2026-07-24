<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addIndustry } = useLandingContent()

// Per-row upload state so each card shows its own spinner/error.
const uploadingIndex = ref(-1)
const uploadError = ref('')

async function uploadImage(item, i, event) {
    const file = event.target.files?.[0]
    event.target.value = '' // allow re-selecting the same file later
    if (!file) return
    uploadingIndex.value = i
    uploadError.value = ''
    try {
        await ensureCsrf()
        const fd = new FormData()
        fd.append('image', file)
        fd.append('folder', 'uploads')
        const { data } = await api.post('uploads/image', fd, { headers: { 'Content-Type': 'multipart/form-data' } })
        item.image = data.data.url
    } catch (e) {
        uploadError.value = e?.response?.data?.message || t('landing_admin.image_upload_failed')
    } finally {
        uploadingIndex.value = -1
    }
}
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
        <p v-if="uploadError" class="lp-err text-sm mb-2" style="color: var(--red);">{{ uploadError }}</p>
        <div class="space-y-3">
            <div v-for="(it, i) in content.industries.items" :key="i"
                class="rounded-xl p-3 flex items-start gap-3" style="background: var(--page); border: 1px solid var(--line);">
                <!-- Image thumbnail / uploader. Falls back to the emoji icon when no image. -->
                <label class="shrink-0 cursor-pointer relative block" style="width:72px;height:72px;" :title="t('landing_admin.industry_image')">
                    <span v-if="it.image" class="block w-full h-full rounded-lg bg-center bg-cover"
                        :style="{ backgroundImage: `url(${it.image})`, border: '1px solid var(--line)' }"></span>
                    <span v-else class="grid place-items-center w-full h-full rounded-lg text-2xl"
                        style="background: var(--card); border: 1px dashed var(--line);">{{ it.icon || '🖼️' }}</span>
                    <span v-if="uploadingIndex === i" class="absolute inset-0 grid place-items-center rounded-lg text-xs"
                        style="background: rgba(0,0,0,.5); color:#fff;">{{ t('common.saving') }}</span>
                    <input type="file" accept="image/*" class="hidden" @change="(e) => uploadImage(it, i, e)" />
                </label>

                <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-2">
                        <span class="label">{{ t('landing_admin.icon') }}</span>
                        <input v-model="it.icon" class="input" style="width: 60px; text-align: center;" maxlength="4" />
                        <button v-if="it.image" type="button" class="btn btn-ghost btn-sm" @click="it.image = ''">{{ t('landing_admin.remove_image') }}</button>
                    </div>
                    <BiField v-model:en="it.text.en" v-model:ar="it.text.ar" />
                </div>

                <div class="flex flex-col gap-1 shrink-0">
                    <button class="icon-btn" :disabled="i === 0" @click="move(content.industries.items, i, -1)">↑</button>
                    <button class="icon-btn" :disabled="i === content.industries.items.length - 1" @click="move(content.industries.items, i, 1)">↓</button>
                    <button class="icon-btn icon-btn-danger" @click="removeAt(content.industries.items, i)">✕</button>
                </div>
            </div>
        </div>
    </AdminSection>
</template>
