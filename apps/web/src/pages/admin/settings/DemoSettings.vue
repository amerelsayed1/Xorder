<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'
import { publicOrigin } from '../../../lib/host.js'

const { t } = useI18n()
const { content, move, removeAt, addStep } = useLandingContent()

const demoPreviewUrl = computed(() => {
    const slug = content.value?.demo?.restaurant_slug?.trim()
    return slug ? `${publicOrigin()}/r/${slug}` : ''
})
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_demo')" open>
        <template #actions>
            <label class="flex items-center gap-2 label" style="cursor:pointer">
                <input type="checkbox" v-model="content.demo.enabled" /> {{ t('landing_admin.demo_enabled') }}
            </label>
        </template>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.demo.title.en" v-model:ar="content.demo.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" textarea v-model:en="content.demo.text.en" v-model:ar="content.demo.text.ar" />
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <BiField :label="t('landing_admin.l_demo_button')" v-model:en="content.demo.button.en" v-model:ar="content.demo.button.ar" />
                <label class="block"><span class="label">{{ t('landing_admin.l_demo_slug') }}</span>
                    <input v-model="content.demo.restaurant_slug" class="input mt-1.5" placeholder="xorderrest" dir="ltr" />
                    <span class="page-sub" style="font-size:12px">{{ t('landing_admin.demo_slug_hint') }}</span>
                    <a v-if="demoPreviewUrl" :href="demoPreviewUrl" target="_blank" rel="noopener" class="mt-1.5 inline-block" style="font-size:13px;color:var(--accent)">{{ t('landing_admin.preview_demo') }} ↗</a></label>
            </div>
        </div>
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.flow_steps') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addStep">{{ t('landing_admin.add_step') }}</button>
        </div>
        <BiField :label="t('landing_admin.l_section_title')" class="mb-3" v-model:en="content.steps.title.en" v-model:ar="content.steps.title.ar" />
        <div class="space-y-3">
            <div v-for="(s, i) in content.steps.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2">
                    <span class="label">{{ t('landing_admin.step', { n: i + 1 }) }}</span>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.steps.items, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.steps.items.length - 1" @click="move(content.steps.items, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.steps.items, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_title')" v-model:en="s.title.en" v-model:ar="s.title.ar" />
                <BiField :label="t('landing_admin.l_text')" class="mt-2" textarea v-model:en="s.text.en" v-model:ar="s.text.ar" />
            </div>
        </div>
    </AdminSection>
</template>
