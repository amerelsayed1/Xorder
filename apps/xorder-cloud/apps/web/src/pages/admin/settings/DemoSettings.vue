<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'
import { menuUrl, asPreview } from '../../../lib/host.js'

const { t } = useI18n()
const { content, move, removeAt, addStep } = useLandingContent()

const demoPreviewUrl = computed(() => {
    const slug = content.value?.demo?.restaurant_slug?.trim()
    return slug ? asPreview(menuUrl(slug)) : ''
})
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_demo')" open>
        <template #actions>
            <label class="flex items-center gap-2 label" style="cursor:pointer;min-height:44px">
                <input type="checkbox" v-model="content.demo.enabled" /> {{ t('landing_admin.demo_enabled') }}
            </label>
        </template>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.demo.title.en" v-model:ar="content.demo.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" textarea v-model:en="content.demo.text.en" v-model:ar="content.demo.text.ar" />
        </div>
        <div class="set-group">
            <BiField :label="t('landing_admin.l_demo_button')" v-model:en="content.demo.button.en" v-model:ar="content.demo.button.ar" />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label class="block"><span class="label">{{ t('landing_admin.l_demo_slug') }}</span>
                    <input v-model="content.demo.restaurant_slug" class="input mt-1.5" placeholder="xorderrest" dir="ltr" />
                    <span class="set-help block mt-1.5">{{ t('landing_admin.demo_slug_hint') }}</span>
                    <a v-if="demoPreviewUrl" :href="demoPreviewUrl" target="_blank" rel="noopener" class="demo-link">{{ t('landing_admin.preview_demo') }} <i class="pi pi-external-link" aria-hidden="true" /></a></label>
            </div>
        </div>

        <div class="set-sub-head">
            <h3 class="h-card" style="font-size:15px">{{ t('landing_admin.flow_steps') }}</h3>
            <button class="btn btn-ghost btn-sm" @click="addStep">{{ t('landing_admin.add_step') }}</button>
        </div>
        <BiField :label="t('landing_admin.l_section_title')" class="mb-4" v-model:en="content.steps.title.en" v-model:ar="content.steps.title.ar" />
        <p v-if="!content.steps.items.length" class="set-empty">{{ t('landing_admin.empty_items') }}</p>
        <div v-else class="space-y-3">
            <div v-for="(s, i) in content.steps.items" :key="i" class="set-item">
                <div class="set-item-head">
                    <span class="label" style="margin:0">{{ t('landing_admin.step', { n: i + 1 }) }}</span>
                    <div class="set-item-actions">
                        <button class="icon-btn" :disabled="i === 0" :aria-label="t('landing_admin.move_up')" @click="move(content.steps.items, i, -1)"><i class="pi pi-arrow-up" aria-hidden="true" /></button>
                        <button class="icon-btn" :disabled="i === content.steps.items.length - 1" :aria-label="t('landing_admin.move_down')" @click="move(content.steps.items, i, 1)"><i class="pi pi-arrow-down" aria-hidden="true" /></button>
                        <button class="icon-btn icon-btn-danger" :aria-label="t('landing_admin.remove')" @click="removeAt(content.steps.items, i)"><i class="pi pi-trash" aria-hidden="true" /></button>
                    </div>
                </div>
                <div class="set-group">
                    <BiField :label="t('landing_admin.l_title')" v-model:en="s.title.en" v-model:ar="s.title.ar" />
                    <BiField :label="t('landing_admin.l_text')" textarea v-model:en="s.text.en" v-model:ar="s.text.ar" />
                </div>
            </div>
        </div>
    </AdminSection>
</template>

<style scoped>
.demo-link { display: inline-flex; align-items: center; gap: 6px; margin-top: 8px; min-height: 32px; font-size: 14px; font-weight: 500;
    color: var(--p-primary-700); }
.demo-link:hover { text-decoration: underline; }
.demo-link .pi { font-size: 12px; }
</style>
