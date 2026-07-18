import { computed } from 'vue'
import { useAuth } from '@xorder/api-client/auth.js'

// Which name/description language fields a form should collect.
//
// Every text field is stored twice (_ar/_en), but a restaurant that isn't
// bilingual only needs its default language — showing both fields is just
// noise. When `bilingual` is false we render a single field for the default
// language; the other column stays empty (both are nullable server-side, and
// validation only requires one of the pair).
export function useMenuLang() {
    const auth = useAuth()
    const defaultLang = computed(() => auth.restaurant?.default_language || 'ar')
    const bilingual = computed(() => auth.restaurant?.bilingual !== false)
    // Languages to render, default language first.
    const langs = computed(() =>
        bilingual.value
            ? (defaultLang.value === 'ar' ? ['ar', 'en'] : ['en', 'ar'])
            : [defaultLang.value]
    )
    return { defaultLang, bilingual, langs }
}
