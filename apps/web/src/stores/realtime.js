// One shared heartbeat + notification store for the dashboard.
//
// Replaces the several independent polling loops that used to live in
// DashboardLayout / LiveBoardView / OrdersView. A single
// visibility-aware timer hits the consolidated /dashboard/pulse endpoint with
// an If-None-Match header, so an idle tab's poll is a bare 304 with no body,
// and a backgrounded tab doesn't poll at all. Views subscribe to `tick` to
// know when to refresh their own lists instead of each keeping a timer.
import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '@xorder/api-client/api.js'

export const useRealtime = defineStore('realtime', () => {
    // Badge counts (null = the plan doesn't have that feature, so never shown).
    const newOrders = ref(0)
    const newRequests = ref(0)
    const unread = ref(0)
    const latestId = ref(0)

    // Notification-centre list (loaded lazily when the bell opens).
    const notifications = ref([])
    const listLoading = ref(false)

    let etag = null
    let timer = null
    let intervalMs = 10_000
    const tickHandlers = new Set()

    /** Register a callback fired after every pulse that observed a change. */
    function onTick(fn) {
        tickHandlers.add(fn)
        return () => tickHandlers.delete(fn)
    }

    // `force` runs even on a hidden tab — used for the first load and for the
    // refresh when the tab is refocused. The recurring interval passes no force,
    // so a backgrounded tab stops polling until it's visible again.
    async function pulse(force = false) {
        if (!force && typeof document !== 'undefined' && document.hidden) return
        try {
            const res = await api.get('api/dashboard/pulse', {
                headers: etag ? { 'If-None-Match': etag } : {},
                // 304 is success here, not an error.
                validateStatus: (s) => s === 200 || s === 304,
            })
            if (res.status === 304) return
            etag = res.headers?.etag || etag
            const d = res.data?.data || {}
            if (d.new_orders != null) newOrders.value = d.new_orders
            if (d.new_requests != null) newRequests.value = d.new_requests
            unread.value = d.unread_notifications ?? unread.value
            latestId.value = d.latest_notification_id ?? latestId.value
            tickHandlers.forEach((fn) => { try { fn(d) } catch { /* isolate handlers */ } })
        } catch { /* transient — keep the last known counts */ }
    }

    function onVisible() { if (!document.hidden) pulse(true) }

    /** Begin polling. Idempotent — a second call just updates the interval. */
    function start(ms = 10_000) {
        intervalMs = ms
        if (timer) return
        pulse(true) // first load runs even if the tab is opened in the background
        timer = setInterval(() => pulse(), intervalMs)
        if (typeof document !== 'undefined') document.addEventListener('visibilitychange', onVisible)
    }

    function stop() {
        clearInterval(timer)
        timer = null
        if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVisible)
    }

    /** Fetch the latest notifications for the bell dropdown. */
    async function fetchNotifications() {
        listLoading.value = true
        try {
            const { data } = await api.get('api/dashboard/notifications')
            notifications.value = data.data || []
        } catch { /* leave the last list in place */ }
        finally { listLoading.value = false }
    }

    /** Mark one read — optimistic, so the badge/row update feels instant. */
    async function markRead(id) {
        const n = notifications.value.find((x) => x.id === id)
        if (n && !n.read) { n.read = true; unread.value = Math.max(0, unread.value - 1) }
        try { await api.patch(`api/dashboard/notifications/${id}/read`) } catch { /* pulse will reconcile */ }
    }

    async function markAllRead() {
        notifications.value.forEach((n) => { n.read = true })
        unread.value = 0
        try { await api.post('api/dashboard/notifications/read-all') } catch { /* pulse will reconcile */ }
    }

    return {
        newOrders, newRequests, unread, latestId, notifications, listLoading,
        start, stop, pulse, onTick, fetchNotifications, markRead, markAllRead,
    }
})
