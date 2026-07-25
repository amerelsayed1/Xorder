// Flowbite-styled ApexCharts presets.
//
// Flowbite's charts are ApexCharts under the hood (https://flowbite.com/docs/plugins/charts/);
// these builders reproduce Flowbite's option style (rounded columns, dashed grid,
// borderless axes, gradient area fills) but pull their palette from the app's own
// design tokens so charts match the active portal theme (warm / indigo) instead of
// Flowbite's fixed blue.

const FONT = 'Tajawal, ui-sans-serif, system-ui, sans-serif'

// Resolve the theme tokens as they compute on `el` (which lives inside the
// `.theme-warm` / `.theme-indigo` portal, so the CSS variables are in scope).
export function getChartColors(el) {
    const s = getComputedStyle(el)
    const v = (name, fallback) => (s.getPropertyValue(name).trim() || fallback)
    return {
        accent: v('--accent', '#f89a06'),
        accentDark: v('--accent-dark', '#d9850a'),
        green: v('--green', '#1f7a3d'),
        amber: v('--amber', '#a9711a'),
        red: v('--red', '#c0392b'),
        gray: v('--gray', '#6b748c'),
        ink: v('--ink', '#2a1e14'),
        body: v('--body', '#5a4d3d'),
        muted: v('--muted', '#8a7c68'),
        line: v('--line', '#ece5d9'),
        card: v('--card', '#ffffff'),
    }
}

const axisLabelStyle = (c) => ({
    style: { fontFamily: FONT, colors: c.muted, fontSize: '11px', fontWeight: 500 },
})

// Build a tooltip config. Only attach `y` when we have a formatter — leaving
// `y: undefined` overwrites ApexCharts' own default and makes it throw.
function tooltipCfg(money, extra = {}) {
    const t = { style: { fontFamily: FONT }, ...extra }
    if (money) t.y = { formatter: (val) => fmtMoney(val) }
    return t
}

// Grouped/single vertical column chart (Flowbite "Column chart").
export function columnChart({ colors, categories, series, palette, height = 260, money = false }) {
    return {
        series,
        colors: palette || [colors.accent],
        chart: { type: 'bar', height, fontFamily: FONT, toolbar: { show: false }, background: 'transparent' },
        plotOptions: {
            bar: { horizontal: false, columnWidth: series.length > 1 ? '70%' : '55%', borderRadius: 4, borderRadiusApplication: 'end' },
        },
        dataLabels: { enabled: false },
        legend: { show: series.length > 1, fontFamily: FONT, labels: { colors: colors.body }, markers: { radius: 12 } },
        stroke: { show: true, width: series.length > 1 ? 0 : 0, colors: ['transparent'] },
        fill: { opacity: 1 },
        states: { hover: { filter: { type: 'darken', value: 0.9 } } },
        grid: { show: true, borderColor: colors.line, strokeDashArray: 4, padding: { left: 4, right: 4, top: -8 } },
        tooltip: tooltipCfg(money, { shared: true, intersect: false }),
        xaxis: {
            categories,
            labels: axisLabelStyle(colors),
            axisBorder: { show: false },
            axisTicks: { show: false },
        },
        yaxis: { show: true, labels: { ...axisLabelStyle(colors), formatter: money ? (val) => fmtMoney(val) : (val) => fmtCompact(val) } },
    }
}

// Horizontal ranking bar chart (Flowbite "Bar chart" horizontal).
export function barChart({ colors, categories, series, height = 260, color, money = false }) {
    return {
        series,
        colors: [color || colors.accent],
        chart: { type: 'bar', height, fontFamily: FONT, toolbar: { show: false }, background: 'transparent' },
        plotOptions: { bar: { horizontal: true, borderRadius: 4, borderRadiusApplication: 'end', barHeight: '65%' } },
        dataLabels: { enabled: false },
        legend: { show: false },
        fill: { opacity: 1 },
        states: { hover: { filter: { type: 'darken', value: 0.9 } } },
        grid: { show: true, borderColor: colors.line, strokeDashArray: 4, padding: { left: 4, right: 12, top: -14 } },
        tooltip: tooltipCfg(money),
        xaxis: { categories, labels: { ...axisLabelStyle(colors), formatter: money ? (val) => fmtMoney(val) : undefined }, axisBorder: { show: false }, axisTicks: { show: false } },
        yaxis: { labels: axisLabelStyle(colors) },
    }
}

// Smooth gradient area chart (Flowbite "Area chart") — for compact trends.
export function areaChart({ colors, categories, series, height = 220, color }) {
    const stroke = color || colors.accent
    return {
        series,
        colors: [stroke],
        chart: { type: 'area', height, fontFamily: FONT, sparkline: { enabled: false }, toolbar: { show: false }, dropShadow: { enabled: false }, background: 'transparent' },
        fill: {
            type: 'gradient',
            gradient: { shadeIntensity: 1, opacityFrom: 0.45, opacityTo: 0, stops: [0, 90] },
        },
        dataLabels: { enabled: false },
        stroke: { width: 3, curve: 'smooth' },
        legend: { show: false },
        grid: { show: true, borderColor: colors.line, strokeDashArray: 4, padding: { left: 4, right: 4, top: -12 } },
        tooltip: { style: { fontFamily: FONT }, x: { show: true } },
        xaxis: { categories, labels: axisLabelStyle(colors), axisBorder: { show: false }, axisTicks: { show: false }, tooltip: { enabled: false } },
        yaxis: { show: true, labels: { ...axisLabelStyle(colors), formatter: (val) => fmtCompact(val) } },
    }
}

// Donut chart (Flowbite "Donut chart") — for distributions.
export function donutChart({ colors, labels, series, palette, height = 260 }) {
    return {
        series,
        labels,
        colors: palette,
        chart: { type: 'donut', height, fontFamily: FONT, toolbar: { show: false }, background: 'transparent' },
        stroke: { colors: [colors.card], width: 2 },
        plotOptions: { pie: { donut: { size: '68%', labels: { show: false } } } },
        dataLabels: { enabled: false },
        legend: { position: 'bottom', fontFamily: FONT, labels: { colors: colors.body }, markers: { radius: 12 } },
        tooltip: { style: { fontFamily: FONT } },
        grid: { padding: { top: -8 } },
    }
}

function fmtCompact(v) {
    const n = Number(v) || 0
    if (Math.abs(n) >= 1000) return (n / 1000).toLocaleString(undefined, { maximumFractionDigits: 1 }) + 'k'
    return String(Math.round(n))
}

function fmtMoney(v) {
    return Number(v || 0).toLocaleString(undefined, { maximumFractionDigits: 0 })
}
