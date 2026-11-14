// Firebase Cloud Messaging (web push) registration for the admin dashboard.
//
// Reads the public config injected by /firebase-config.js. Everything is a
// safe no-op until that config is filled in, so the app runs fine without it.
import { initializeApp, getApps } from 'firebase/app'
import { getMessaging, getToken, onMessage, isSupported } from 'firebase/messaging'
import api from '@xorder/api-client/api.js'

const cfg = (typeof window !== 'undefined' && window.__FIREBASE_CONFIG__) || {}

let messaging = null
let registered = false

export function pushConfigured() {
    return Boolean(cfg.apiKey && cfg.vapidKey)
}

async function ensureMessaging() {
    if (messaging) return messaging
    if (!pushConfigured()) return null
    if (!(await isSupported().catch(() => false))) return null
    const app = getApps().length ? getApps()[0] : initializeApp(cfg)
    messaging = getMessaging(app)
    return messaging
}

/**
 * Register this device for push. Call from a user gesture (it may prompt for
 * notification permission). Idempotent. `onForeground(payload)` fires for
 * messages received while the tab is focused. Returns true once a token is sent.
 */
export async function registerPush(onForeground) {
    if (registered) return true
    if (!pushConfigured() || !('serviceWorker' in navigator) || !('Notification' in window)) return false

    const m = await ensureMessaging()
    if (!m) return false

    let perm = Notification.permission
    if (perm === 'default') perm = await Notification.requestPermission()
    if (perm !== 'granted') return false

    let swReg
    try {
        swReg = await navigator.serviceWorker.register('/firebase-messaging-sw.js')
    } catch (err) {
        return false
    }

    const token = await getToken(m, { vapidKey: cfg.vapidKey, serviceWorkerRegistration: swReg }).catch(() => null)
    if (!token) return false

    try {
        await api.post('api/dashboard/push/token', { token, platform: 'web' })
    } catch (err) { /* token save failed — will retry next session */ }

    if (onForeground) onMessage(m, onForeground)
    registered = true
    return true
}
