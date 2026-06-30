<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'
import BiField from '../../components/BiField.vue'

const { t } = useI18n()

const content = ref(null)
const loading = ref(true)
const saving = ref(false)
const errorList = ref([])
const savedFlash = ref(false)

onMounted(load)

async function load() {
    loading.value = true
    const { data } = await api.get('api/admin/landing-content')
    content.value = data.data
    loading.value = false
}

const bi = () => ({ en: '', ar: '' })

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
function addPlan() {
    content.value.pricing.plans.push({ name: bi(), price: bi(), per: bi(), note: bi(), popular: false, features: [] })
}
function addPlanFeature(plan) { plan.features.push(bi()) }

async function save() {
    saving.value = true
    errorList.value = []
    try {
        await ensureCsrf()
        const { data } = await api.put('api/admin/landing-content', { content: content.value })
        content.value = data.data
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
                <!-- HERO -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_hero') }}</h2>
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_badge')" v-model:en="content.hero.badge.en" v-model:ar="content.hero.badge.ar" />
                        <BiField :label="t('landing_admin.l_title')" v-model:en="content.hero.title.en" v-model:ar="content.hero.title.ar" />
                        <BiField :label="t('landing_admin.l_subtitle')" textarea v-model:en="content.hero.sub.en" v-model:ar="content.hero.sub.ar" />
                        <BiField :label="t('landing_admin.l_primary_button')" v-model:en="content.hero.cta.en" v-model:ar="content.hero.cta.ar" />
                        <BiField :label="t('landing_admin.l_secondary_link')" v-model:en="content.hero.secondary.en" v-model:ar="content.hero.secondary.ar" />
                    </div>
                </section>

                <!-- PROOF POINTS -->
                <section class="card p-5 mt-5">
                    <div class="flex items-center justify-between mb-4">
                        <h2 class="h-card">{{ t('landing_admin.sec_proof') }}</h2>
                        <button class="btn btn-ghost btn-sm" @click="addProof">{{ t('landing_admin.add') }}</button>
                    </div>
                    <div class="space-y-3">
                        <div v-for="(p, i) in content.proof" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                            <div class="flex items-center justify-between mb-2">
                                <span class="label">#{{ i + 1 }}</span>
                                <div class="flex gap-1">
                                    <button class="icon-btn" :disabled="i === 0" :title="t('landing_admin.move_up')" @click="move(content.proof, i, -1)">↑</button>
                                    <button class="icon-btn" :disabled="i === content.proof.length - 1" :title="t('landing_admin.move_down')" @click="move(content.proof, i, 1)">↓</button>
                                    <button class="icon-btn icon-btn-danger" :title="t('landing_admin.remove')" @click="removeAt(content.proof, i)">✕</button>
                                </div>
                            </div>
                            <BiField :label="t('landing_admin.l_title')" v-model:en="p.title.en" v-model:ar="p.title.ar" />
                            <BiField :label="t('landing_admin.l_text')" class="mt-2" v-model:en="p.text.en" v-model:ar="p.text.ar" />
                        </div>
                        <p v-if="!content.proof.length" class="page-sub">{{ t('landing_admin.no_proof') }}</p>
                    </div>
                </section>

                <!-- FEATURES -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_features') }}</h2>
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
                                    <button class="icon-btn" :disabled="i === 0" :title="t('landing_admin.move_up')" @click="move(content.features.items, i, -1)">↑</button>
                                    <button class="icon-btn" :disabled="i === content.features.items.length - 1" :title="t('landing_admin.move_down')" @click="move(content.features.items, i, 1)">↓</button>
                                    <button class="icon-btn icon-btn-danger" :title="t('landing_admin.remove')" @click="removeAt(content.features.items, i)">✕</button>
                                </div>
                            </div>
                            <BiField :label="t('landing_admin.l_title')" v-model:en="f.title.en" v-model:ar="f.title.ar" />
                            <BiField :label="t('landing_admin.l_text')" class="mt-2" textarea v-model:en="f.text.en" v-model:ar="f.text.ar" />
                        </div>
                    </div>
                </section>

                <!-- STEPS -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_steps') }}</h2>
                    <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.steps.title.en" v-model:ar="content.steps.title.ar" />
                    <div class="flex items-center justify-between mt-5 mb-3">
                        <span class="label">{{ t('landing_admin.steps') }}</span>
                        <button class="btn btn-ghost btn-sm" @click="addStep">{{ t('landing_admin.add_step') }}</button>
                    </div>
                    <div class="space-y-3">
                        <div v-for="(s, i) in content.steps.items" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                            <div class="flex items-center justify-between mb-2">
                                <span class="label">{{ t('landing_admin.step', { n: i + 1 }) }}</span>
                                <div class="flex gap-1">
                                    <button class="icon-btn" :disabled="i === 0" :title="t('landing_admin.move_up')" @click="move(content.steps.items, i, -1)">↑</button>
                                    <button class="icon-btn" :disabled="i === content.steps.items.length - 1" :title="t('landing_admin.move_down')" @click="move(content.steps.items, i, 1)">↓</button>
                                    <button class="icon-btn icon-btn-danger" :title="t('landing_admin.remove')" @click="removeAt(content.steps.items, i)">✕</button>
                                </div>
                            </div>
                            <BiField :label="t('landing_admin.l_title')" v-model:en="s.title.en" v-model:ar="s.title.ar" />
                            <BiField :label="t('landing_admin.l_text')" class="mt-2" textarea v-model:en="s.text.en" v-model:ar="s.text.ar" />
                        </div>
                    </div>
                </section>

                <!-- PRICING -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_pricing') }}</h2>
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_section_title')" v-model:en="content.pricing.title.en" v-model:ar="content.pricing.title.ar" />
                        <BiField :label="t('landing_admin.l_section_subtitle')" v-model:en="content.pricing.sub.en" v-model:ar="content.pricing.sub.ar" />
                        <BiField :label="t('landing_admin.l_popular_label')" v-model:en="content.pricing.popular_label.en" v-model:ar="content.pricing.popular_label.ar" />
                        <BiField :label="t('landing_admin.l_choose_label')" v-model:en="content.pricing.choose_label.en" v-model:ar="content.pricing.choose_label.ar" />
                    </div>
                    <div class="flex items-center justify-between mt-5 mb-3">
                        <span class="label">{{ t('landing_admin.plans') }}</span>
                        <button class="btn btn-ghost btn-sm" @click="addPlan">{{ t('landing_admin.add_plan') }}</button>
                    </div>
                    <div class="space-y-4">
                        <div v-for="(plan, i) in content.pricing.plans" :key="i" class="rounded-xl p-3" style="background: var(--page); border: 1px solid var(--line);">
                            <div class="flex items-center justify-between mb-2">
                                <label class="flex items-center gap-2 label" style="cursor: pointer;">
                                    <input type="checkbox" v-model="plan.popular" /> {{ t('landing_admin.most_popular') }}
                                </label>
                                <div class="flex gap-1">
                                    <button class="icon-btn" :disabled="i === 0" :title="t('landing_admin.move_up')" @click="move(content.pricing.plans, i, -1)">↑</button>
                                    <button class="icon-btn" :disabled="i === content.pricing.plans.length - 1" :title="t('landing_admin.move_down')" @click="move(content.pricing.plans, i, 1)">↓</button>
                                    <button class="icon-btn icon-btn-danger" :title="t('landing_admin.remove')" @click="removeAt(content.pricing.plans, i)">✕</button>
                                </div>
                            </div>
                            <BiField :label="t('landing_admin.l_name')" v-model:en="plan.name.en" v-model:ar="plan.name.ar" />
                            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2">
                                <BiField :label="t('landing_admin.l_price')" v-model:en="plan.price.en" v-model:ar="plan.price.ar" />
                                <BiField :label="t('landing_admin.l_per')" v-model:en="plan.per.en" v-model:ar="plan.per.ar" />
                            </div>
                            <BiField :label="t('landing_admin.l_note')" class="mt-2" v-model:en="plan.note.en" v-model:ar="plan.note.ar" />
                            <div class="flex items-center justify-between mt-3 mb-2">
                                <span class="label">{{ t('landing_admin.plan_features') }}</span>
                                <button class="btn btn-ghost btn-sm" @click="addPlanFeature(plan)">{{ t('landing_admin.add_feature') }}</button>
                            </div>
                            <div class="space-y-2">
                                <div v-for="(feat, fi) in plan.features" :key="fi" class="flex items-start gap-2">
                                    <BiField class="flex-1" v-model:en="feat.en" v-model:ar="feat.ar" />
                                    <button class="icon-btn icon-btn-danger mt-1" :title="t('landing_admin.remove')" @click="removeAt(plan.features, fi)">✕</button>
                                </div>
                            </div>
                        </div>
                    </div>
                </section>

                <!-- CTA -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_cta') }}</h2>
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_title')" v-model:en="content.cta.title.en" v-model:ar="content.cta.title.ar" />
                        <BiField :label="t('landing_admin.l_subtitle')" textarea v-model:en="content.cta.sub.en" v-model:ar="content.cta.sub.ar" />
                        <BiField :label="t('landing_admin.l_button')" v-model:en="content.cta.button.en" v-model:ar="content.cta.button.ar" />
                        <BiField :label="t('landing_admin.l_whatsapp_label')" v-model:en="content.cta.whatsapp_label.en" v-model:ar="content.cta.whatsapp_label.ar" />
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-4">
                        <label class="block">
                            <span class="label">{{ t('landing_admin.contact_email') }}</span>
                            <input v-model="content.contact.email" class="input mt-1.5" type="email" placeholder="hello@xorder.app" />
                        </label>
                        <label class="block">
                            <span class="label">{{ t('landing_admin.whatsapp_number') }}</span>
                            <input v-model="content.contact.whatsapp" class="input mt-1.5" placeholder="201234567890" />
                        </label>
                    </div>
                </section>

                <!-- FOOTER -->
                <section class="card p-5 mt-5">
                    <h2 class="h-card mb-4">{{ t('landing_admin.sec_footer') }}</h2>
                    <div class="space-y-3">
                        <BiField :label="t('landing_admin.l_tagline')" v-model:en="content.footer.tagline.en" v-model:ar="content.footer.tagline.ar" />
                        <BiField :label="t('landing_admin.l_rights')" v-model:en="content.footer.rights.en" v-model:ar="content.footer.rights.ar" />
                    </div>
                </section>

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
