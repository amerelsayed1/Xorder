import { ref, computed, onMounted, nextTick } from 'vue'
import { fetchMenu } from '../api.js'

export function useMenu(slug) {
    const payload = ref(null)
    const loading = ref(true)
    const error = ref(false)
    const unavailable = ref(false)
    const activeCat = ref('')
    const view = ref('menu')

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

    async function scrollTo(id) {
        activeCat.value = id
        await nextTick()
        const target = document.getElementById(`section-${id}`)
        if (!target) return

        const toolbar = document.querySelector('.menu-toolbar')
        const stickyTop = toolbar ? Number.parseFloat(window.getComputedStyle(toolbar).top) || 0 : 0
        const stickyBottom = stickyTop + (toolbar?.offsetHeight || 0)
        const targetTop = window.scrollY + target.getBoundingClientRect().top - stickyBottom

        window.scrollTo({ top: Math.max(0, targetTop), behavior: 'smooth' })
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
