import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import api, { ensureCsrf } from '@xorder/api-client/api.js'

// Shared singleton state for the landing-page CMS. The Settings area splits the
// editor across several sub-pages, but they all bind to this one document so a
// single Save persists everything regardless of which page you're on.
const content = ref(null)
const loading = ref(false)
const saving = ref(false)
const errorList = ref([])
const savedFlash = ref(false)
// Snapshot of the last loaded/saved document. isDirty compares the live editor
// state against it so the Settings area can warn before discarding edits.
const savedSnapshot = ref('')
const isDirty = computed(() =>
    !!content.value && JSON.stringify(content.value) !== savedSnapshot.value
)

const bi = () => ({ en: '', ar: '' })

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
    // FAQ items: back-fill the visibility flag on rows saved before FAQ existed.
    c.faq?.items?.forEach((f) => { if (f.enabled === undefined) f.enabled = true })
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
function addIndustry() { content.value.industries.items.push({ icon: '🍽️', image: '', text: bi() }) }
function addFaq() { content.value.faq.items.push({ enabled: true, q: bi(), a: bi() }) }
function addPlan() {
    content.value.pricing.plans.push({ name: bi(), subtitle: bi(), price_label: bi(), recommended: false, enabled: true, features: [] })
}
function addPlanFeature(plan) { plan.features.push(bi()) }

export function useLandingContent() {
    const { t } = useI18n()

    async function load() {
        loading.value = true
        errorList.value = []
        const { data } = await api.get('api/admin/landing-content')
        content.value = normalize(data.data)
        savedSnapshot.value = JSON.stringify(content.value)
        loading.value = false
    }

    async function save() {
        saving.value = true
        errorList.value = []
        try {
            await ensureCsrf()
            const { data } = await api.put('api/admin/landing-content', { content: content.value })
            content.value = normalize(data.data)
            savedSnapshot.value = JSON.stringify(content.value)
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

    return {
        content, loading, saving, errorList, savedFlash, isDirty,
        bi, load, save, move, removeAt,
        addProof, addFeature, addStep, addBenefit, addProblem,
        addThird, addXorder, addIndustry, addPlan, addPlanFeature, addFaq,
    }
}
