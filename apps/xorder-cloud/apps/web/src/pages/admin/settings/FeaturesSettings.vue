<script setup>
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addFeature } = useLandingContent()

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
        // Let axios set multipart/form-data WITH its boundary; forcing the header
        // manually strips the boundary and the file won't parse.
        const { data } = await api.post('api/uploads/image', fd)
        item.image = data.data.url
    } catch (e) {
        uploadError.value = e?.response?.data?.message || t('landing_admin.image_upload_failed')
    } finally {
        uploadingIndex.value = -1
    }
}
</script>

<template>
    <!-- FEATURES -->
    <AdminSection :title="t('landing_admin.sec_features')" open>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.features.title.en" v-model:ar="content.features.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" textarea v-model:en="content.features.sub.en" v-model:ar="content.features.sub.ar" />
        </div>
        <div class="set-sub-head">
            <h3 class="h-card" style="font-size:15px">{{ t('landing_admin.feature_cards') }}</h3>
            <button class="btn btn-ghost btn-sm" @click="addFeature">{{ t('landing_admin.add_card') }}</button>
        </div>
        <p v-if="uploadError" class="set-err mb-3" role="alert">{{ uploadError }}</p>
        <p v-if="!content.features.items.length" class="set-empty">{{ t('landing_admin.empty_items') }}</p>
        <div v-else class="space-y-3">
            <div v-for="(f, i) in content.features.items" :key="i" class="set-item">
                <div class="set-item-head">
                    <div class="flex items-center gap-3 min-w-0">
                    <label class="thumb" :title="t('landing_admin.feature_image')">
                        <span v-if="f.image" class="thumb-img" :style="{ backgroundImage: `url(${f.image})` }"></span>
                        <span v-else class="thumb-empty">
                            <template v-if="f.icon">{{ f.icon }}</template>
                            <i v-else class="pi pi-image" aria-hidden="true" />
                        </span>
                        <span class="thumb-up" aria-hidden="true"><i class="pi pi-upload" /></span>
                        <span v-if="uploadingIndex === i" class="thumb-busy">{{ t('common.saving') }}</span>
                        <input type="file" accept="image/*" class="sr-only" :aria-label="t('landing_admin.feature_image')" @change="(e) => uploadImage(f, i, e)" />
                    </label>
                        <!-- Icon only matters as the fallback when there's no image. -->
                        <template v-if="!f.image">
                            <label class="flex items-center gap-2"><span class="label">{{ t('landing_admin.icon') }}</span>
                                <input v-model="f.icon" class="input icon-field" maxlength="4" /></label>
                        </template>
                        <button v-else type="button" class="btn btn-ghost btn-sm" @click="f.image = ''">{{ t('landing_admin.remove_image') }}</button>
                    </div>
                    <div class="set-item-actions">
                        <button class="icon-btn" :disabled="i === 0" :aria-label="t('landing_admin.move_up')" @click="move(content.features.items, i, -1)"><i class="pi pi-arrow-up" aria-hidden="true" /></button>
                        <button class="icon-btn" :disabled="i === content.features.items.length - 1" :aria-label="t('landing_admin.move_down')" @click="move(content.features.items, i, 1)"><i class="pi pi-arrow-down" aria-hidden="true" /></button>
                        <button class="icon-btn icon-btn-danger" :aria-label="t('landing_admin.remove')" @click="removeAt(content.features.items, i)"><i class="pi pi-trash" aria-hidden="true" /></button>
                    </div>
                </div>
                <div class="set-group">
                    <BiField :label="t('landing_admin.l_title')" v-model:en="f.title.en" v-model:ar="f.title.ar" />
                    <BiField :label="t('landing_admin.l_text')" textarea v-model:en="f.text.en" v-model:ar="f.text.ar" />
                </div>
            </div>
        </div>
    </AdminSection>
</template>

<style scoped>
/* Image / icon tile for a card. The emoji (if any) is user data; with neither
   image nor icon a neutral image glyph shows. */
.thumb { position: relative; display: block; flex: none; width: 64px; height: 64px; cursor: pointer; }
.thumb-img { display: block; width: 100%; height: 100%; border-radius: 10px; border: 1px solid var(--line);
    background-position: center; background-size: cover; }
.thumb-empty { display: grid; place-items: center; width: 100%; height: 100%; border-radius: 10px; font-size: 26px;
    background: var(--card); border: 1px dashed var(--muted); color: var(--body); }
.thumb:hover .thumb-empty, .thumb:hover .thumb-img { border-color: var(--accent); }
.thumb:focus-within { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 10px; }
.thumb-up { position: absolute; inset-block-end: -6px; inset-inline-end: -6px; width: 24px; height: 24px; border-radius: 50%;
    display: grid; place-items: center; background: var(--ink); color: var(--card); font-size: 11px; }
.thumb-busy { position: absolute; inset: 0; display: grid; place-items: center; border-radius: 10px; font-size: 12px;
    background: var(--ink); color: var(--card); opacity: .85; }
.icon-field { width: 64px; text-align: center; margin-top: 0; }
</style>
