<script setup>
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'

// Shared filter bar for both analytics reports. All state lives in the
// useReportFilters() context handed in as `ctx`; this component is just the UI
// plus the debounced "apply on change" behaviour, so the client never has to
// hunt for an Apply button to see fresh numbers.
const props = defineProps({
    ctx: { type: Object, required: true },
    showGroup: { type: Boolean, default: false },   // group-by (products report only)
    showExport: { type: Boolean, default: false },  // CSV/Excel (products report only)
    exporting: { type: String, default: '' },
})
const emit = defineEmits(['apply', 'export'])

const { t } = useI18n()
const showMore = ref(false)

// Re-run the report a short beat after any effective filter changes. Watching
// the serialized query params means we react to real changes only (and collapse
// a multi-field preset into a single reload).
let timer
watch(() => JSON.stringify(props.ctx.params()), () => {
    clearTimeout(timer)
    timer = setTimeout(() => emit('apply'), 350)
})

function applyNow() {
    clearTimeout(timer)
    emit('apply')
}

function reset() {
    props.ctx.resetFilters()   // watcher above reloads with the cleared filters
    showMore.value = false
}
</script>

<template>
    <div class="card p-4 rep-filters-card">
        <!-- Quick date presets -->
        <div class="rep-block">
            <span class="rep-block-label">{{ t('rep.quick_range') }}</span>
            <div class="rep-chips">
                <button
                    v-for="p in ctx.PRESETS" :key="p.key" type="button"
                    class="rep-chip" :class="{ active: ctx.activePreset === p.key }"
                    @click="ctx.applyPreset(p.key)"
                >{{ p.label() }}</button>
            </div>
        </div>

        <!-- Date range + time-of-day -->
        <div class="rep-block rep-ranges">
            <div>
                <span class="rep-block-label">{{ t('rep.date_range') }}</span>
                <div class="rep-inline">
                    <input v-model="ctx.state.dateFrom" type="date" class="input" :aria-label="t('rep.date_from')" />
                    <span class="rep-sep">–</span>
                    <input v-model="ctx.state.dateTo" type="date" class="input" :aria-label="t('rep.date_to')" />
                </div>
            </div>
            <div>
                <span class="rep-block-label">
                    {{ t('rep.time_of_day') }}
                    <button
                        v-if="ctx.state.timeFrom || ctx.state.timeTo" type="button" class="rep-clear"
                        @click="ctx.state.timeFrom = ''; ctx.state.timeTo = ''"
                    >{{ t('rep.clear') }}</button>
                </span>
                <div class="rep-inline">
                    <input v-model="ctx.state.timeFrom" type="time" class="input" :aria-label="t('rep.time_from')" />
                    <span class="rep-sep">–</span>
                    <input v-model="ctx.state.timeTo" type="time" class="input" :aria-label="t('rep.time_to')" />
                </div>
            </div>
        </div>

        <!-- Days of week -->
        <div class="rep-block">
            <span class="rep-block-label">
                {{ t('rep.days_of_week') }}
                <button
                    v-if="ctx.state.daysOfWeek.length" type="button" class="rep-clear"
                    @click="ctx.state.daysOfWeek = []"
                >{{ t('rep.clear') }}</button>
            </span>
            <div class="rep-chips">
                <button
                    v-for="d in ctx.WEEKDAYS" :key="d" type="button"
                    class="rep-chip rep-day" :class="{ active: ctx.state.daysOfWeek.includes(d) }"
                    @click="ctx.toggleDay(d)"
                >{{ ctx.weekdayLabel(d) }}</button>
            </div>
        </div>

        <!-- Group by (products report only) -->
        <div v-if="showGroup" class="rep-block">
            <span class="rep-block-label">{{ t('rep.group_by') }}</span>
            <div class="segmented rep-segmented">
                <button
                    type="button" :class="{ active: ctx.state.groupBy === 'period' }"
                    @click="ctx.state.groupBy = 'period'"
                >{{ t('rep.by_period') }}</button>
                <button
                    type="button" :class="{ active: ctx.state.groupBy === 'hour' }"
                    @click="ctx.state.groupBy = 'hour'"
                >{{ t('rep.by_hour') }}</button>
                <button
                    type="button" :class="{ active: ctx.state.groupBy === 'day' }"
                    @click="ctx.state.groupBy = 'day'"
                >{{ t('rep.by_day') }}</button>
            </div>
        </div>

        <!-- More filters (collapsed by default) -->
        <button type="button" class="rep-more-toggle" @click="showMore = !showMore">
            <i :class="showMore ? 'pi pi-chevron-up' : 'pi pi-chevron-down'"></i>
            {{ showMore ? t('rep.fewer_filters') : t('rep.more_filters') }}
        </button>

        <div v-show="showMore" class="rep-more">
            <label class="rep-field">
                <span class="label">{{ t('rep.branch') }}</span>
                <select v-model="ctx.state.branchId" class="input">
                    <option value="">{{ t('rep.all_branches') }}</option>
                    <option v-for="b in ctx.branches" :key="b.id" :value="b.id">{{ ctx.localName(b, 'name') }}</option>
                </select>
            </label>
            <label class="rep-field">
                <span class="label">{{ t('rep.area') }}</span>
                <select v-model="ctx.state.areaId" class="input">
                    <option value="">{{ t('rep.all_areas') }}</option>
                    <option v-for="a in ctx.areas" :key="a.id" :value="a.id">{{ ctx.localName(a, 'name') }}</option>
                </select>
            </label>
            <label class="rep-field">
                <span class="label">{{ t('rep.type') }}</span>
                <select v-model="ctx.state.areaType" class="input">
                    <option value="">{{ t('rep.all_types') }}</option>
                    <option v-for="ty in ctx.AREA_TYPES" :key="ty" :value="ty">{{ ctx.typeLabel(ty) }}</option>
                </select>
            </label>
            <label class="rep-field">
                <span class="label">{{ t('nav.orders') }}</span>
                <select v-model="ctx.state.orderType" class="input">
                    <option value="">{{ t('rep.all_order_types') }}</option>
                    <option v-for="ot in ctx.ORDER_TYPES" :key="ot" :value="ot">{{ t('order_type.' + ot) }}</option>
                </select>
            </label>
        </div>

        <!-- Footer -->
        <div class="rep-footer">
            <label class="rep-check">
                <input v-model="ctx.state.includeCancelled" type="checkbox" />
                <span>{{ t('rep.include_cancelled') }}</span>
            </label>
            <div class="flex-1"></div>
            <button class="btn btn-ghost btn-sm" @click="reset">{{ t('rep.reset') }}</button>
            <button class="btn btn-accent btn-sm" @click="applyNow">{{ t('rep.apply') }}</button>
            <template v-if="showExport">
                <button class="btn btn-ghost btn-sm" :disabled="!!exporting" @click="emit('export', 'csv')">
                    {{ exporting === 'csv' ? t('rep.exporting') : t('rep.export_csv') }}
                </button>
                <button class="btn btn-ghost btn-sm" :disabled="!!exporting" @click="emit('export', 'xlsx')">
                    {{ exporting === 'xlsx' ? t('rep.exporting') : t('rep.export_xlsx') }}
                </button>
            </template>
        </div>
    </div>
</template>

<style scoped>
.rep-filters-card { display: flex; flex-direction: column; gap: 16px; }

.rep-block { display: flex; flex-direction: column; gap: 8px; }
.rep-block-label { font-size: 12px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .03em; display: flex; align-items: center; gap: 8px; }

/* Chip rows — presets and weekday toggles share the look. */
.rep-chips { display: flex; flex-wrap: wrap; gap: 8px; }
.rep-chip {
    font-size: 13px; font-weight: 600; padding: 7px 14px; border-radius: 999px;
    border: 1px solid var(--line); background: var(--card); color: var(--body);
    cursor: pointer; transition: all .12s ease; white-space: nowrap;
}
.rep-chip:hover { border-color: var(--accent); color: var(--accent); }
.rep-chip.active { background: var(--accent); border-color: var(--accent); color: #fff; }
.rep-day { min-width: 52px; text-align: center; }

.rep-clear { font-size: 11.5px; font-weight: 600; color: var(--accent); background: none; border: none; cursor: pointer; padding: 0; text-transform: none; letter-spacing: 0; }
.rep-clear:hover { text-decoration: underline; }

/* Date/time range: two inline pairs, wrapping on small screens. */
.rep-ranges { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, max-content)); gap: 16px; }
.rep-inline { display: flex; align-items: center; gap: 8px; }
.rep-inline .input { margin-top: 0; width: auto; min-width: 128px; }
.rep-sep { color: var(--muted); }

.rep-segmented { align-self: flex-start; }
.rep-segmented button { font-size: 13px; font-weight: 600; padding: 6px 14px; border: none; background: none; border-radius: 8px; color: var(--muted); cursor: pointer; }
.rep-segmented button.active { color: var(--ink); }

.rep-more-toggle { align-self: flex-start; display: inline-flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: var(--accent); background: none; border: none; cursor: pointer; padding: 2px 0; }
.rep-more-toggle i { font-size: 11px; }

.rep-more { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; padding-top: 2px; }
.rep-field { display: flex; flex-direction: column; }
.rep-field .label { font-size: 12px; color: var(--muted); }
.rep-field .input { margin-top: 4px; }

.rep-footer { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; border-top: 1px solid var(--line); padding-top: 14px; }
.rep-check { display: inline-flex; align-items: center; gap: 7px; font-size: 13.5px; color: var(--body); cursor: pointer; }
.rep-check input { width: 15px; height: 15px; }
.flex-1 { flex: 1; }
.btn-sm { padding: 6px 13px; font-size: 12.5px; }

@media (max-width: 640px) {
    .rep-ranges { grid-template-columns: 1fr; }
    .rep-inline .input { flex: 1; min-width: 0; }
}
</style>
