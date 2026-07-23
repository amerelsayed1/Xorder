<script setup>
import { useI18n } from 'vue-i18n'
import Skeleton from '@xorder/ui/Skeleton.vue'

const props = defineProps({
    rows: { type: Array, default: () => [] },
    loading: { type: Boolean, default: false },
    showTenant: { type: Boolean, default: true },
})

const { t, te } = useI18n()

// Category → icon (PrimeIcons) + accent colour.
const CATEGORY_META = {
    auth: { icon: 'pi-sign-in', color: '#6366f1' },
    restaurant: { icon: 'pi-building', color: '#0ea5e9' },
    user: { icon: 'pi-user', color: '#8b5cf6' },
    menu_item: { icon: 'pi-book', color: '#f59e0b' },
    category: { icon: 'pi-tags', color: '#f59e0b' },
    order: { icon: 'pi-shopping-cart', color: '#10b981' },
    branch: { icon: 'pi-map-marker', color: '#0ea5e9' },
    dining_area: { icon: 'pi-th-large', color: '#0ea5e9' },
    dining_table: { icon: 'pi-stop', color: '#0ea5e9' },
}
const meta = (cat) => CATEGORY_META[cat] || { icon: 'pi-circle', color: 'var(--muted)' }

const catLabel = (cat) => te(`audit.cat.${cat}`) ? t(`audit.cat.${cat}`) : cat
const roleLabel = (role) => role && te(`audit.role.${role}`) ? t(`audit.role.${role}`) : (role || t('audit.system'))

function actionVerb(action) {
    // "restaurant.updated" → "updated"
    return action.includes('.') ? action.slice(action.indexOf('.') + 1).replaceAll('_', ' ') : action
}

// Human summary: prefer the stored description, else derive from the action key.
function summary(row) {
    if (row.description) return row.description
    return `${catLabel(row.category)} ${actionVerb(row.action)}`
}

// Flatten properties.changes → ["status: ACTIVE → SUSPENDED", …]
function changeLines(row) {
    const changes = row.properties?.changes
    if (!changes) return []
    return Object.entries(changes).map(([field, { old, new: nu }]) =>
        `${field}: ${fmtVal(old)} → ${fmtVal(nu)}`)
}
function fmtVal(v) {
    if (v === null || v === undefined || v === '') return '—'
    if (typeof v === 'object') return JSON.stringify(v)
    return String(v)
}

function fmtWhen(iso) {
    if (!iso) return ''
    const d = new Date(iso)
    return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
}
</script>

<template>
    <div>
        <ul v-if="loading" class="audit-feed" aria-hidden="true">
            <li v-for="n in 6" :key="n" class="audit-row">
                <Skeleton w="34px" h="34px" rounded="9px" />
                <div class="audit-body flex flex-col gap-2">
                    <Skeleton w="45%" h="14px" />
                    <Skeleton w="30%" h="12px" />
                </div>
            </li>
        </ul>
        <div v-else-if="!rows.length" class="py-10 text-center" style="color:var(--muted)">{{ t('audit.none') }}</div>

        <ul v-else class="audit-feed">
            <li v-for="row in rows" :key="row.id" class="audit-row">
                <span class="audit-icon" :style="{ background: meta(row.category).color + '1a', color: meta(row.category).color }">
                    <i class="pi" :class="meta(row.category).icon"></i>
                </span>
                <div class="audit-body">
                    <div class="audit-line">
                        <span class="audit-summary">{{ summary(row) }}</span>
                        <span class="audit-cat">{{ catLabel(row.category) }}</span>
                    </div>
                    <div class="audit-meta">
                        <span class="audit-actor">{{ row.actor.name || roleLabel(row.actor.role) }}</span>
                        <span class="audit-role">{{ roleLabel(row.actor.role) }}</span>
                        <template v-if="showTenant && row.tenant">
                            <span class="audit-sep">·</span>
                            <span>{{ row.tenant.name }}</span>
                        </template>
                        <span class="audit-sep">·</span>
                        <span class="audit-time">{{ fmtWhen(row.created_at) }}</span>
                    </div>
                    <ul v-if="changeLines(row).length" class="audit-changes">
                        <li v-for="(line, i) in changeLines(row)" :key="i" class="mono">{{ line }}</li>
                    </ul>
                </div>
            </li>
        </ul>
    </div>
</template>

<style scoped>
.audit-feed { display: flex; flex-direction: column; }
.audit-row { display: flex; gap: 12px; padding: 12px 2px; border-top: 1px solid var(--line); }
.audit-row:first-child { border-top: none; }
.audit-icon { flex-shrink: 0; width: 34px; height: 34px; border-radius: 9px; display: grid; place-items: center; font-size: 15px; }
.audit-body { min-width: 0; flex: 1; }
.audit-line { display: flex; align-items: center; gap: 10px; justify-content: space-between; }
.audit-summary { color: var(--ink); font-weight: 550; font-size: 14px; }
.audit-cat { flex-shrink: 0; font-size: 11px; color: var(--muted); background: var(--accent-soft); padding: 2px 8px; border-radius: 20px; }
.audit-meta { display: flex; align-items: center; gap: 7px; flex-wrap: wrap; margin-top: 3px; font-size: 12.5px; color: var(--muted); }
.audit-actor { color: var(--body); font-weight: 550; }
.audit-role { font-size: 10.5px; text-transform: uppercase; letter-spacing: .03em; background: var(--line); color: var(--body); padding: 1px 7px; border-radius: 20px; }
.audit-sep { opacity: .5; }
.audit-changes { margin-top: 6px; padding: 8px 10px; background: var(--accent-soft); border-radius: 9px; font-size: 12px; color: var(--body); display: flex; flex-direction: column; gap: 2px; }
</style>
