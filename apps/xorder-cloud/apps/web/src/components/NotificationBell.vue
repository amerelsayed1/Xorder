<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useRealtime } from '../stores/realtime.js'

const { t } = useI18n()
const router = useRouter()
const rt = useRealtime()

const open = ref(false)
const panel = ref(null)
const btn = ref(null)

// Map each notification type to a named route (base-URL independent) and an
// icon. The API already sends a localized title/body, so the bell only styles.
const ROUTE_BY_TYPE = {
    'order.created': 'dashboard.orders',
    'bill_request.created': 'dashboard.home',
    'review.created': 'dashboard.reviews',
    'subscription.expiring': 'dashboard.profile',
}
const ICON_BY_TYPE = {
    'order.created': 'pi pi-shopping-bag',
    'bill_request.created': 'pi pi-receipt',
    'review.created': 'pi pi-star',
    'subscription.expiring': 'pi pi-exclamation-triangle',
}
function iconFor(type) { return ICON_BY_TYPE[type] || 'pi pi-info-circle' }

const badge = computed(() => (rt.unread > 99 ? '99+' : rt.unread))

function toggle() {
    open.value = !open.value
    if (open.value) rt.fetchNotifications()
}
function close() { open.value = false }

function onDocClick(e) {
    if (!open.value) return
    if (panel.value?.contains(e.target) || btn.value?.contains(e.target)) return
    close()
}
function onKey(e) { if (e.key === 'Escape') close() }

onMounted(() => {
    document.addEventListener('click', onDocClick)
    document.addEventListener('keydown', onKey)
})
onUnmounted(() => {
    document.removeEventListener('click', onDocClick)
    document.removeEventListener('keydown', onKey)
})

async function openNotification(n) {
    rt.markRead(n.id)
    close()
    const name = ROUTE_BY_TYPE[n.type]
    if (name) router.push({ name })
    else if (n.url) router.push(n.url)
}

// Compact relative time — the list is "what just happened", not a calendar.
function relTime(iso) {
    if (!iso) return ''
    const diff = Date.now() - new Date(iso).getTime()
    const m = Math.floor(diff / 60000)
    if (m < 1) return t('notifications.just_now')
    if (m < 60) return t('notifications.minutes_ago', { n: m })
    const h = Math.floor(m / 60)
    if (h < 24) return t('notifications.hours_ago', { n: h })
    return t('notifications.days_ago', { n: Math.floor(h / 24) })
}
</script>

<template>
    <div class="nbell">
        <button
            ref="btn"
            type="button"
            class="nbell-trigger"
            :aria-label="t('notifications.aria_open')"
            :aria-expanded="open"
            @click="toggle"
        >
            <i class="pi pi-bell" aria-hidden="true" />
            <span v-if="rt.unread > 0" class="nbell-badge">{{ badge }}</span>
        </button>

        <Transition name="nbell-pop">
            <div v-if="open" ref="panel" class="nbell-panel" role="dialog" :aria-label="t('notifications.title')">
                <header class="nbell-head">
                    <strong>{{ t('notifications.title') }}</strong>
                    <button
                        v-if="rt.unread > 0"
                        type="button"
                        class="nbell-mark"
                        @click="rt.markAllRead()"
                    >
                        {{ t('notifications.mark_all_read') }}
                    </button>
                </header>

                <div class="nbell-list">
                    <div v-if="rt.listLoading && !rt.notifications.length" class="nbell-empty">
                        <i class="pi pi-spin pi-spinner" aria-hidden="true" />
                    </div>
                    <div v-else-if="!rt.notifications.length" class="nbell-empty">
                        <i class="pi pi-check-circle" aria-hidden="true" />
                        <span>{{ t('notifications.empty') }}</span>
                    </div>
                    <button
                        v-for="n in rt.notifications"
                        :key="n.id"
                        type="button"
                        class="nbell-item"
                        :class="{ unread: !n.read }"
                        @click="openNotification(n)"
                    >
                        <span class="nbell-icon" :class="'t-' + n.type.split('.')[0]">
                            <i :class="iconFor(n.type)" aria-hidden="true" />
                        </span>
                        <span class="nbell-body">
                            <span class="nbell-title">{{ n.title }}</span>
                            <span v-if="n.body" class="nbell-sub">{{ n.body }}</span>
                            <span class="nbell-time">{{ relTime(n.created_at) }}</span>
                        </span>
                        <span v-if="!n.read" class="nbell-dot" aria-hidden="true" />
                    </button>
                </div>
            </div>
        </Transition>
    </div>
</template>

<style scoped>
.nbell { position: relative; }

.nbell-trigger {
    position: relative; display: inline-flex; align-items: center; justify-content: center;
    width: 40px; height: 40px; border-radius: 50%; border: none; cursor: pointer;
    background: transparent; color: var(--p-text-color);
}
.nbell-trigger:hover { background: var(--p-surface-100); }
.nbell-trigger .pi-bell { font-size: 18px; }

.nbell-badge {
    position: absolute; top: 2px; inset-inline-end: 2px; min-width: 18px; height: 18px;
    padding: 0 5px; border-radius: 9px; background: #ef4444; color: #fff;
    font-size: 11px; font-weight: 700; line-height: 18px; text-align: center;
    box-shadow: 0 0 0 2px var(--p-surface-0, #fff);
}

.nbell-panel {
    position: absolute; inset-block-start: calc(100% + 8px); inset-inline-end: 0; z-index: 70;
    width: 360px; max-width: 92vw; max-height: 70vh; display: flex; flex-direction: column;
    background: var(--p-surface-0, #fff); color: var(--p-text-color);
    border: 1px solid var(--p-surface-200); border-radius: 14px;
    box-shadow: 0 18px 44px rgba(30, 20, 5, .22); overflow: hidden;
}
.nbell-head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 16px; border-bottom: 1px solid var(--p-surface-200);
}
.nbell-head strong { font-size: 15px; font-weight: 700; }
.nbell-mark {
    background: none; border: none; cursor: pointer; padding: 4px 6px;
    color: var(--p-primary-color); font-size: 12px; font-weight: 600;
}
.nbell-mark:hover { text-decoration: underline; }

.nbell-list { overflow-y: auto; }

.nbell-empty {
    display: flex; flex-direction: column; align-items: center; gap: 8px;
    padding: 34px 16px; color: var(--p-text-muted-color, #94a3b8); font-size: 13px;
}
.nbell-empty .pi { font-size: 22px; }

.nbell-item {
    width: 100%; display: flex; align-items: flex-start; gap: 11px;
    padding: 12px 16px; border: none; border-bottom: 1px solid var(--p-surface-100);
    background: transparent; cursor: pointer; text-align: start;
}
.nbell-item:hover { background: var(--p-surface-50, #f8fafc); }
.nbell-item.unread { background: color-mix(in srgb, var(--p-primary-color) 7%, transparent); }
.nbell-item.unread:hover { background: color-mix(in srgb, var(--p-primary-color) 12%, transparent); }

.nbell-icon {
    flex: none; width: 34px; height: 34px; border-radius: 50%;
    display: inline-flex; align-items: center; justify-content: center;
    background: var(--p-surface-100); color: var(--p-text-color); font-size: 15px;
}
.nbell-icon.t-order { background: #fff1e2; color: #c2610a; }
.nbell-icon.t-bill_request { background: #e8f1ff; color: #2563eb; }
.nbell-icon.t-review { background: #fef6e0; color: #d19b00; }
.nbell-icon.t-subscription { background: #fee2e2; color: #dc2626; }

.nbell-body { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
.nbell-title { font-size: 13.5px; font-weight: 600; line-height: 1.35; }
.nbell-sub {
    font-size: 12.5px; color: var(--p-text-muted-color, #64748b); line-height: 1.35;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.nbell-time { font-size: 11px; color: var(--p-text-muted-color, #94a3b8); margin-top: 1px; }

.nbell-dot { flex: none; align-self: center; width: 8px; height: 8px; border-radius: 50%; background: var(--p-primary-color); }

.nbell-pop-enter-active, .nbell-pop-leave-active { transition: transform .16s ease, opacity .16s ease; }
.nbell-pop-enter-from, .nbell-pop-leave-to { transform: translateY(-8px); opacity: 0; }
</style>
