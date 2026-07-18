<script setup>
// Placeholder rows for list/table views while data loads.
import Skeleton from './Skeleton.vue'

defineProps({ rows: { type: Number, default: 6 } })
</script>

<template>
    <div>
        <div v-for="n in rows" :key="n" class="flex items-center gap-3 px-5 py-3.5 border-t first:border-t-0" style="border-color:var(--line)">
            <Skeleton w="44px" h="44px" rounded="10px" />
            <div class="flex-1 space-y-2">
                <Skeleton w="38%" h="13px" />
                <Skeleton w="22%" h="11px" />
            </div>
            <Skeleton class="hidden sm:block" w="64px" h="24px" rounded="999px" />
            <Skeleton w="28px" h="28px" rounded="8px" />
        </div>
    </div>
</template>
