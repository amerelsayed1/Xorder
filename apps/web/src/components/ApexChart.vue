<script setup>
// Thin Vue wrapper around ApexCharts (Flowbite's charting engine).
//
// `build` receives the resolved theme colors (read from the mounted element so
// the active portal theme applies) and returns a full ApexCharts option object —
// use the presets in lib/charts.js. Pass `redraw` a reactive value; whenever it
// changes the chart is rebuilt so it stays in sync with the data and locale.
import { ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import { getChartColors } from '../lib/charts.js'

const props = defineProps({
    build: { type: Function, required: true }, // (colors) => apexOptions
    redraw: { default: null },
})

const el = ref(null)
let chart = null
let destroyed = false

// ApexCharts is ~216 KB gzipped — a third of everything a dashboard page pulls.
// Importing it statically meant the page couldn't paint until the whole library
// arrived, on every view that shows a chart. Loading it here defers that cost
// past first paint: the page renders, then the chart fills in. Memoised, so
// several charts on one page share a single fetch.
let apexPromise = null
function loadApex() {
    apexPromise ??= import('apexcharts').then(m => m.default)
    return apexPromise
}

async function render() {
    if (!el.value) return
    const ApexCharts = await loadApex()
    // The component can unmount while the chunk is in flight.
    if (destroyed || !el.value) return
    const options = props.build(getChartColors(el.value))
    if (chart) chart.destroy()
    chart = new ApexCharts(el.value, options)
    chart.render()
}

onMounted(render)
watch(() => props.redraw, () => nextTick(render), { deep: true })
onBeforeUnmount(() => { destroyed = true; chart?.destroy(); chart = null })
</script>

<template>
    <div ref="el"></div>
</template>
