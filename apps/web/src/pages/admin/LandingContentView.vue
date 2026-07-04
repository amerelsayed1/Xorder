<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import BiField from '../../components/BiField.vue'
import AdminSection from '../../components/AdminSection.vue'
import { publicOrigin } from '../../lib/host.js'

const { t } = useI18n()

const demoPreviewUrl = computed(() => {
    const slug = content.value?.demo?.restaurant_slug?.trim()
    return slug ? `${publicOrigin()}/r/${slug}` : ''
})

const content = ref(null)
const loading = ref(true)
const saving = ref(false)
const errorList = ref([])
const savedFlash = ref(false)

onMounted(load)

const bi = () => ({ en: '', ar: '' })

async function load() {
    loading.value = true
    const { data } = await api.get('api/admin/landing-content')
    content.value = normalize(data.data)
    loading.value = false
}

// Guarantee every section/field the editor binds to exists, even on rows saved
// before a section was introduced. Defaults are already merged server-side, but
// list items (packages) need per-item back-filling here.
function normalize(c) {
    c.pricing.plans.forEach((p) => {
        p.subtitle ??= p.note ?? bi()
        p.price_label ??= p.price ?? bi()
        if (p.recommended === undefined) p.recommended = p.popular ?? false
        if (p.enabled === undefined) p.enabled = true
        p.features ??= []
    })
    return c
}

// --- repeater helpers (add / remove / reorder) ---
function move(arr, i, dir) {
    const j = i + dir
    if (j < 0 || j >= arr.length) return
    const [item] = arr.splice(i, 1)
    arr.splice(j, 0, item)
}
function removeAt(arr, i) { arr.splice(i, 1) }

function addProof() { content.value.proof.push({ title: bi(), text: bi() }) }
function addFeature() { content.value.features.items.push({ icon: '★', title: bi(), text: bi() }) }
function addStep() { content.value.steps.items.push({ title: bi(), text: bi() }) }
function addBenefit() { content.value.offer.items.push({ icon: '★', text: bi() }) }
function addProblem() { content.value.problem.problems.push({ text: bi() }) }
function addThird() { content.value.no_commission.third_party.push({ text: bi() }) }
function addXorder() { content.value.no_commission.xorder.push({ text: bi() }) }
function addIndustry() { content.value.industries.items.push({ icon: '🍽️', text: bi() }) }
function addPlan() {
    content.value.pricing.plans.push({ name: bi(), subtitle: bi(), price_label: bi(), recommended: false, enabled: true, features: [] })
}
function addPlanFeature(plan) { plan.features.push(bi()) }

async function save() {
    saving.value = true
    errorList.value = []
    try {
        await ensureCsrf()
        const { data } = await api.put('api/admin/landing-content', { content: content.value })
        content.value = normalize(data.data)
        savedFlash.value = true
        setTimeout(() => { savedFlash.value = false }, 2500)
        window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch (e) {
        if (e.response?.status === 422) {
            errorList.value = Object.values(e.response.data.errors || {}).flat()
        } else {
            errorList.value = [t('landing_admin.save_error')]
        }
        window.scrollTo({ top: 0, behavior: 'smooth' })
    } finally {
        saving.value = false
    }
}
</script>

<template>
    <div class="portal theme-indigo">
        <div class="max-w-4xl mx-auto px-5 py-7">
            <!-- Header -->
            <div class="flex items-center justify-between gap-4 flex-wrap">
                <div>
                    <h1 class="page-title">{{ t('landing_admin.title') }}</h1>
                    <p class="page-sub">{{ t('landing_admin.subtitle') }}</p>
                </div>
                <div class="flex items-center gap-3">
                    <span v-if="savedFlash" class="badge badge-green"><span class="dot"></span> {{ t('common.saved') }}</span>
                    <button class="btn btn-accent" :disabled="saving || loading" @click="save">
                        {{ saving ? t('common.saving') : t('admin.save_changes') }}
                    </button>
                </div>
            </div>

            <!-- Errors -->
            <div v-if="errorList.length" class="card mt-5 p-4" style="border-color: var(--red); background: var(--red-soft);">
                <p class="font-semibold mb-1" style="color: var(--red);">{{ t('landing_admin.fix_errors') }}</p>
                <ul class="list-disc ps-5 text-sm" style="color: var(--red);">
                    <li v-for="(msg, i) in errorList" :key="i">{{ msg }}</li>
                </ul>
            </div>

            <div v-if="loading" class="card mt-5 p-8 text-center page-sub">{{ t('common.loading') }}</div>

            <template v-else-if="content">
                <!-- SEO -->
                <AdminSection :title="t('landing_admin.sec_seo')" open>
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.seo_title')" v-model:en="content.seo.title.en" v-model:ar="content.seo.title.ar" />
                        <BiField :label="t('landing_admin.seo_desc')" textarea v-model:en="content.seo.description.en" v-model:ar="content.seo.description.ar" />
                        <BiField :label="t('landing_admin.og_title')" v-model:en="content.seo.og_title.en" v-model:ar="content.seo.og_title.ar" />
                        <BiField :label="t('landing_admin.og_desc')" textarea v-model:en="content.seo.og_description.en" v-model:ar="content.seo.og_description.ar" />
                        <label class="block"><span class="label">{{ t('landing_admin.og_image') }}</span>
                            <input v-model="content.seo.og_image" class="input mt-1.5" placeholder="https://…" maxlength="500" /></label>
                    </div>
                </AdminSection>

                <!-- HERO -->
                <AdminSection :title="t('landing_admin.sec_hero')">
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_badge')" v-model:en="content.hero.badge.en" v-model:ar="content.hero.badge.ar" />
                        <BiField :label="t('landing_admin.l_title')" v-model:en="content.hero.title.en" v-model:ar="content.hero.title.ar" />
                        <BiField :label="t('landing_admin.l_subtitle')" textarea v-model:en="content.hero.sub.en" v-model:ar="content.hero.sub.ar" />
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                            <BiField :label="t('landing_admin.l_primary_button')" v-model:en="content.hero.cta.en" v-model:ar="content.hero.cta.ar" />
                            <label class="block"><span class="label">{{ t('landing_admin.l_primary_link') }}</span>
                                <input v-model="content.hero.primary_link" class="input mt-1.5" placeholder="#lead" /></label>
                        </div>
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                            <BiField :label="t('landing_admin.l_secondary_button')" v-model:en="content.hero.secondary.en" v-model:ar="content.hero.secondary.ar" />
                            <label class="block"><span class="label">{{ t('landing_admin.l_secondary_link') }}</span>
                                <input v-model="content.hero.secondary_link" class="input mt-1.5" :placeholder="t('landing_admin.demo_link_ph')" /></label>
                        </div>
                        <BiField :label="t('landing_admin.l_no_commission_label')" v-model:en="content.hero.no_commission_label.en" v-model:ar="content.hero.no_commission_label.ar" />
                        <BiField :label="t('landing_admin.l_ready_label')" v-model:en="content.hero.ready_label.en" v-model:ar="content.hero.ready_label.ar" />
                        <BiField :label="t('landing_admin.l_whatsapp_label')" v-model:en="content.hero.whatsapp_label.en" v-model:ar="content.hero.whatsapp_label.ar" />
                    </div>
                </AdminSection>

                <!-- WHATSAPP SETTINGS -->
                <AdminSection :title="t('landing_admin.sec_whatsapp')">
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <label class="block"><span class="label">{{ t('landing_admin.wa_number') }}</span>
                            <input v-model="content.whatsapp.number" class="input mt-1.5" placeholder="201234567890" dir="ltr" /></label>
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

                <!-- PROOF POINTS -->
                <AdminSection :title="t('landing_admin.sec_proof')">
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
                <AdminSection :title="t('landing_admin.sec_offer')">
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
                <AdminSection :title="t('landing_admin.sec_problem')">
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
                <AdminSection :title="t('landing_admin.sec_no_commission')">
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

                <!-- FEATURES -->
                <AdminSection :title="t('landing_admin.sec_features')">
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.features.title.en" v-model:ar="content.features.title.ar" />
                        <BiField :label="t('landing_admin.l_section_subtitle')" textarea v-model:en="content.features.sub.en" v-model:ar="content.features.sub.ar" />
                    </div>
                    <div class="flex items-center justify-between mt-5 mb-3">
                        <span class="label">{{ t('landing_admin.feature_cards') }}</span>
                        <button class="btn btn-ghost btn-sm" @click="addFeature">{{ t('landing_admin.add_card') }}</button>
                    </div>
                    <div class="space-y-3">
                        <div v-for="(f, i) in content.features.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                            <div class="flex items-center justify-between mb-2 gap-2">
                                <div class="flex items-center gap-2">
                                    <span class="label">{{ t('landing_admin.icon') }}</span>
                                    <input v-model="f.icon" class="input" style="width: 64px; text-align: center;" maxlength="4" />
                                </div>
                                <div class="flex gap-1">
                                    <button class="icon-btn" :disabled="i === 0" @click="move(content.features.items, i, -1)">↑</button>
                                    <button class="icon-btn" :disabled="i === content.features.items.length - 1" @click="move(content.features.items, i, 1)">↓</button>
                                    <button class="icon-btn icon-btn-danger" @click="removeAt(content.features.items, i)">✕</button>
                                </div>
                            </div>
                            <BiField :label="t('landing_admin.l_title')" v-model:en="f.title.en" v-model:ar="f.title.ar" />
                            <BiField :label="t('landing_admin.l_text')" class="mt-2" textarea v-model:en="f.text.en" v-model:ar="f.text.ar" />
                        </div>
                    </div>
                </AdminSection>

                <!-- DEMO + STEPS -->
                <AdminSection :title="t('landing_admin.sec_demo')">
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

                <!-- PACKAGES -->
                <AdminSection :title="t('landing_admin.sec_packages')">
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

                <!-- INDUSTRIES -->
                <AdminSection :title="t('landing_admin.sec_industries')">
                    <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.industries.title.en" v-model:ar="content.industries.title.ar" />
                    <BiField :label="t('landing_admin.l_section_subtitle')" class="mt-2" v-model:en="content.industries.sub.en" v-model:ar="content.industries.sub.ar" />
                    <div class="flex items-center justify-between mt-5 mb-3">
                        <span class="label">{{ t('landing_admin.industries') }}</span>
                        <button class="btn btn-ghost btn-sm" @click="addIndustry">{{ t('landing_admin.add') }}</button>
                    </div>
                    <div class="space-y-3">
                        <div v-for="(it, i) in content.industries.items" :key="i" class="flex items-start gap-2">
                            <input v-model="it.icon" class="input mt-1" style="width:56px;text-align:center" maxlength="4" />
                            <BiField class="flex-1" v-model:en="it.text.en" v-model:ar="it.text.ar" />
                            <button class="icon-btn icon-btn-danger mt-1" @click="removeAt(content.industries.items, i)">✕</button>
                        </div>
                    </div>
                </AdminSection>

                <!-- LEAD FORM -->
                <AdminSection :title="t('landing_admin.sec_lead_form')">
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.lead_form.title.en" v-model:ar="content.lead_form.title.ar" />
                        <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.lead_form.sub.en" v-model:ar="content.lead_form.sub.ar" />
                        <BiField :label="t('landing_admin.l_button')" v-model:en="content.lead_form.button.en" v-model:ar="content.lead_form.button.ar" />
                        <BiField :label="t('landing_admin.l_success')" textarea v-model:en="content.lead_form.success.en" v-model:ar="content.lead_form.success.ar" />
                    </div>
                    <p class="page-sub mt-3" style="font-size:12px">{{ t('landing_admin.leads_hint') }}</p>
                </AdminSection>

                <!-- CTA -->
                <AdminSection :title="t('landing_admin.sec_cta')">
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
                <AdminSection :title="t('landing_admin.sec_footer')">
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_tagline')" v-model:en="content.footer.tagline.en" v-model:ar="content.footer.tagline.ar" />
                        <BiField :label="t('landing_admin.l_rights')" v-model:en="content.footer.rights.en" v-model:ar="content.footer.rights.ar" />
                    </div>
                </AdminSection>

                <!-- Save bar -->
                <div class="flex justify-end mt-6 pb-10">
                    <button class="btn btn-accent" :disabled="saving" @click="save">
                        {{ saving ? t('common.saving') : t('admin.save_changes') }}
                    </button>
                </div>
            </template>
        </div>
    </div>
</template>
