<script setup>
// Shimmer placeholder rows for <table> bodies while data loads.
// Render inside <tbody>; set `cols` to match the table's column count.
import Skeleton from './Skeleton.vue'

defineProps({
    cols: { type: Number, default: 5 },
    rows: { type: Number, default: 6 },
})
</script>

<template>
    <tr v-for="r in rows" :key="r" class="border-t first:border-t-0" style="border-color:var(--line)">
        <td v-for="c in cols" :key="c" class="px-5 py-3.5">
            <Skeleton :w="c === 1 ? '55%' : '40%'" h="13px" />
        </td>
    </tr>
</template>
