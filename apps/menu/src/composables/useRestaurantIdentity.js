import { computed } from 'vue'

export function useRestaurantIdentity(props) {
    const primaryName = computed(() => props.isAr
        ? (props.restaurant?.name_ar || props.restaurant?.name_en || '')
        : (props.restaurant?.name_en || props.restaurant?.name_ar || ''))

    const alternateName = computed(() => props.isAr
        ? props.restaurant?.name_en
        : props.restaurant?.name_ar)

    const initial = computed(() => (
        props.restaurant?.name_en || props.restaurant?.name_ar || 'M'
    ).charAt(0))

    return { primaryName, alternateName, initial }
}
