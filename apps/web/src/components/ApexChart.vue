<script setup>
// Thin Vue wrapper around ApexCharts (Flowbite's charting engine).
//
// `build` receives the resolved theme colors (read from the mounted element so
// the active portal theme applies) and returns a full ApexCharts option object —
// use the presets in lib/charts.js. Pass `redraw` a reactive value; whenever it
// changes the chart is rebuilt so it stays in sync with the data and locale.
import { ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import ApexCharts from 'apexcharts'
import { getChartColors } from '../lib/charts.js'

const props = defineProps({
    build: { type: Function, required: true }, // (colors) => apexOptions
    redraw: { default: null },
})

const el = ref(null)
let chart = null

function render() {
    if (!el.value) return
    const options = props.build(getChartColors(el.value))
    if (chart) chart.destroy()
    chart = new ApexCharts(el.value, options)
    chart.render()
}

onMounted(render)
watch(() => props.redraw, () => nextTick(render), { deep: true })
onBeforeUnmount(() => { chart?.destroy(); chart = null })
</script>

<template>
    <div ref="el"></div>
</template>
