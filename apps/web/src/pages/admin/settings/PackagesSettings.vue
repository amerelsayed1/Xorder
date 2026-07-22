<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addPlan, addPlanFeature } = useLandingContent()
</script>

<template>
    <AdminSection :title="t('landing_admin.sec_packages')" open>
        <div class="space-y-3">
            <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.pricing.title.en" v-model:ar="content.pricing.title.ar" />
            <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.pricing.sub.en" v-model:ar="content.pricing.sub.ar" />
            <BiField :label="t('landing_admin.l_recommended_label')" v-model:en="content.pricing.popular_label.en" v-model:ar="content.pricing.popular_label.ar" />
            <BiField :label="t('landing_admin.l_choose_label')" v-model:en="content.pricing.choose_label.en" v-model:ar="content.pricing.choose_label.ar" />
        </div>
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.packages') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addPlan">{{ t('landing_admin.add_package') }}</button>
        </div>
        <div class="space-y-4">
            <div v-for="(plan, i) in content.pricing.plans" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2 gap-3 flex-wrap">
                    <div class="flex items-center gap-4">
                        <label class="flex items-center gap-2 label" style="cursor: pointer;">
                            <input type="checkbox" v-model="plan.recommended" /> {{ t('landing_admin.recommended') }}
                        </label>
                        <label class="flex items-center gap-2 label" style="cursor: pointer;">
                            <input type="checkbox" v-model="plan.enabled" /> {{ t('landing_admin.visible') }}
                        </label>
                    </div>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.pricing.plans, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.pricing.plans.length - 1" @click="move(content.pricing.plans, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.pricing.plans, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_name')" v-model:en="plan.name.en" v-model:ar="plan.name.ar" />
                <BiField :label="t('landing_admin.l_subtitle')" class="mt-2" textarea v-model:en="plan.subtitle.en" v-model:ar="plan.subtitle.ar" />
                <BiField :label="t('landing_admin.l_price_label')" class="mt-2" v-model:en="plan.price_label.en" v-model:ar="plan.price_label.ar" />
                <div class="flex items-center justify-between mt-3 mb-2">
                    <span class="label">{{ t('landing_admin.plan_features') }}</span>
                    <button class="btn btn-ghost btn-sm" @click="addPlanFeature(plan)">{{ t('landing_admin.add_feature') }}</button>
                </div>
                <div class="space-y-2">
                    <div v-for="(feat, fi) in plan.features" :key="fi" class="flex items-start gap-2">
                        <BiField class="flex-1" v-model:en="feat.en" v-model:ar="feat.ar" />
                        <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(plan.features, fi)">✕</button>
                    </div>
                </div>
            </div>
        </div>
    </AdminSection>
</template>
