import { ref, computed, onMounted, nextTick } from 'vue'
import { fetchMenu } from '../api.js'

export function useMenu(slug) {
    const payload = ref(null)
    const loading = ref(true)
    const error = ref(false)
    const unavailable = ref(false)
    const activeCat = ref('')
    const view = ref('menu')
    // While a category jump is animating, the scroll-spy is muted so it doesn't
    // flicker the active tab through every section the smooth scroll passes.
    const spyLocked = ref(false)

    const restaurant = computed(() => payload.value?.restaurant || {})
    const categories = computed(() => payload.value?.categories || [])
    const combos = computed(() => payload.value?.combos || [])
    const branches = computed(() => payload.value?.branches || [])

    const navCats = computed(() => {
        const list = []
        if (combos.value.length) list.push({ id: 'offers', isOffers: true })
        categories.value.forEach(c => list.push({ id: `cat-${c.id}`, category: c }))
        return list
    })

    async function loadMenu() {
        loading.value = true
        try {
            const res = await fetchMenu(slug)
            if (res.available === false) {
                unavailable.value = true
            } else {
                payload.value = res.data
                activeCat.value = res.data.combos?.length
                    ? 'offers'
                    : (res.data.categories?.[0] ? `cat-${res.data.categories[0].id}` : '')
                document.title = res.data.restaurant?.name_en || res.data.restaurant?.name_ar || 'Menu'
            }
        } catch (err) {
            error.value = true
        } finally {
            loading.value = false
        }
    }

    let unlockTimer = null
    let onSettle = null

    // Release the spy once the smooth scroll has settled — detected by a lull in
    // scroll events — with a timeout backstop for reduced-motion / no-op scrolls.
    function releaseSpyWhenSettled() {
        clearTimeout(unlockTimer)
        if (onSettle) window.removeEventListener('scroll', onSettle)
        let idle = null
        const finish = () => {
            clearTimeout(idle)
            clearTimeout(unlockTimer)
            window.removeEventListener('scroll', onSettle)
            onSettle = null
            spyLocked.value = false
        }
        onSettle = () => {
            clearTimeout(idle)
            idle = setTimeout(finish, 100)
        }
        window.addEventListener('scroll', onSettle, { passive: true })
        unlockTimer = setTimeout(finish, 800)
    }

    // Jump to a category. The vertical offset lives in CSS as
    // `scroll-margin-block-start: var(--stack-h)` on each section, so a plain
    // scrollIntoView lands the section fully below the sticky stack at every
    // width — no hand-computed offsets.
    async function scrollTo(id) {
        activeCat.value = id
        spyLocked.value = true
        await nextTick()
        const target = document.getElementById(`section-${id}`)
        if (!target) { spyLocked.value = false; return }
        target.scrollIntoView({ behavior: 'smooth', block: 'start' })
        releaseSpyWhenSettled()
    }

    function goHome() {
        view.value = 'menu'
        window.scrollTo({ top: 0 })
    }

    function goBranches() {
        view.value = 'branches'
        window.scrollTo({ top: 0 })
    }

    onMounted(() => {
        loadMenu()
    })

    return {
        payload,
        loading,
        error,
        unavailable,
        activeCat,
        spyLocked,
        view,
        restaurant,
        categories,
        combos,
        branches,
        navCats,
        scrollTo,
        goHome,
        goBranches,
    }
}
