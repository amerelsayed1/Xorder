<script setup>
import { useI18n } from 'vue-i18n'
import BiField from '../../../components/BiField.vue'
import AdminSection from '../../../components/AdminSection.vue'
import { useLandingContent } from '../../../composables/useLandingContent.js'

const { t } = useI18n()
const { content, move, removeAt, addProof, addBenefit, addProblem, addThird, addXorder } = useLandingContent()
</script>

<template>
    <!-- PROOF POINTS -->
    <AdminSection :title="t('landing_admin.sec_proof')" open>
        <template #actions>
            <button class="btn btn-ghost btn-sm" @click="addProof">{{ t('landing_admin.add') }}</button>
        </template>
        <div class="space-y-3">
            <div v-for="(p, i) in content.proof" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2">
                    <span class="label">#{{ i + 1 }}</span>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.proof, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.proof.length - 1" @click="move(content.proof, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.proof, i)">✕</button>
                    </div>
                </div>
                <BiField :label="t('landing_admin.l_title')" v-model:en="p.title.en" v-model:ar="p.title.ar" />
                <BiField :label="t('landing_admin.l_text')" class="mt-2" v-model:en="p.text.en" v-model:ar="p.text.ar" />
            </div>
        </div>
    </AdminSection>

    <!-- OFFER -->
    <AdminSection :title="t('landing_admin.sec_offer')" open>
        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.offer.title.en" v-model:ar="content.offer.title.ar" />
        <BiField :label="t('landing_admin.l_section_subtitle')" class="mt-2" textarea v-model:en="content.offer.text.en" v-model:ar="content.offer.text.ar" />
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.benefits') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addBenefit">{{ t('landing_admin.add') }}</button>
        </div>
        <div class="space-y-3">
            <div v-for="(it, i) in content.offer.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <div class="flex items-center justify-between mb-2 gap-2">
                    <div class="flex items-center gap-2">
                        <span class="label">{{ t('landing_admin.icon') }}</span>
                        <input v-model="it.icon" class="input" style="width:64px;text-align:center" maxlength="4" />
                    </div>
                    <div class="flex gap-1">
                        <button class="icon-btn" :disabled="i === 0" @click="move(content.offer.items, i, -1)">↑</button>
                        <button class="icon-btn" :disabled="i === content.offer.items.length - 1" @click="move(content.offer.items, i, 1)">↓</button>
                        <button class="icon-btn icon-btn-danger" @click="removeAt(content.offer.items, i)">✕</button>
                    </div>
                </div>
                <BiField v-model:en="it.text.en" v-model:ar="it.text.ar" />
            </div>
        </div>
    </AdminSection>

    <!-- PROBLEM / SOLUTION -->
    <AdminSection :title="t('landing_admin.sec_problem')" open>
        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.problem.title.en" v-model:ar="content.problem.title.ar" />
        <BiField :label="t('landing_admin.l_section_subtitle')" class="mt-2" v-model:en="content.problem.sub.en" v-model:ar="content.problem.sub.ar" />
        <div class="flex items-center justify-between mt-5 mb-3">
            <span class="label">{{ t('landing_admin.problems') }}</span>
            <button class="btn btn-ghost btn-sm" @click="addProblem">{{ t('landing_admin.add') }}</button>
        </div>
        <div class="space-y-3">
            <div v-for="(p, i) in content.problem.problems" :key="i" class="flex items-start gap-2">
                <BiField class="flex-1" v-model:en="p.text.en" v-model:ar="p.text.ar" />
                <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(content.problem.problems, i)">✕</button>
            </div>
        </div>
        <div class="mt-5 space-y-3">
            <BiField :label="t('landing_admin.l_solution_title')" v-model:en="content.problem.solution_title.en" v-model:ar="content.problem.solution_title.ar" />
            <BiField :label="t('landing_admin.l_solution_text')" textarea v-model:en="content.problem.solution_text.en" v-model:ar="content.problem.solution_text.ar" />
        </div>
    </AdminSection>

    <!-- NO COMMISSION -->
    <AdminSection :title="t('landing_admin.sec_no_commission')" open>
        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.no_commission.title.en" v-model:ar="content.no_commission.title.ar" />
        <BiField :label="t('landing_admin.l_section_subtitle')" class="mt-2" textarea v-model:en="content.no_commission.text.en" v-model:ar="content.no_commission.text.ar" />

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-5">
            <div class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <BiField :label="t('landing_admin.l_compare_title')" v-model:en="content.no_commission.third_party_title.en" v-model:ar="content.no_commission.third_party_title.ar" />
                <div class="flex items-center justify-between mt-3 mb-2">
                    <span class="label">{{ t('landing_admin.third_party') }}</span>
                    <button class="btn btn-ghost btn-sm" @click="addThird">{{ t('landing_admin.add') }}</button>
                </div>
                <div class="space-y-2">
                    <div v-for="(it, i) in content.no_commission.third_party" :key="i" class="flex items-start gap-2">
                        <BiField class="flex-1" v-model:en="it.text.en" v-model:ar="it.text.ar" />
                        <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(content.no_commission.third_party, i)">✕</button>
                    </div>
                </div>
            </div>
            <div class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                <BiField :label="t('landing_admin.l_compare_title')" v-model:en="content.no_commission.xorder_title.en" v-model:ar="content.no_commission.xorder_title.ar" />
                <div class="flex items-center justify-between mt-3 mb-2">
                    <span class="label">{{ t('landing_admin.xorder_pts') }}</span>
                    <button class="btn btn-ghost btn-sm" @click="addXorder">{{ t('landing_admin.add') }}</button>
                </div>
                <div class="space-y-2">
                    <div v-for="(it, i) in content.no_commission.xorder" :key="i" class="flex items-start gap-2">
                        <BiField class="flex-1" v-model:en="it.text.en" v-model:ar="it.text.ar" />
                        <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(content.no_commission.xorder, i)">✕</button>
                    </div>
                </div>
            </div>
        </div>
    </AdminSection>
</template>
