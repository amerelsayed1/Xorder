/* Firebase Cloud Messaging service worker — shows push notifications when the
   dashboard tab is in the background or closed. Loads its config from the same
   editable /firebase-config.js the app uses. No-op until that config is filled. */
importScripts('https://www.gstatic.com/firebasejs/12.16.0/firebase-app-compat.js')
importScripts('https://www.gstatic.com/firebasejs/12.16.0/firebase-messaging-compat.js')
importScripts('/firebase-config.js')

const cfg = self.__FIREBASE_CONFIG__ || {}

if (cfg.apiKey) {
    firebase.initializeApp(cfg)
    const messaging = firebase.messaging()

    messaging.onBackgroundMessage((payload) => {
        const n = payload.notification || {}
        self.registration.showNotification(n.title || 'New order', {
            body: n.body || '',
            icon: '/pwa-192.png',
            badge: '/favicon-32.png',
            tag: 'xorder-order',
            renotify: true,
            requireInteraction: true,
            data: payload.data || {},
        })
    })
}

// A no-op fetch handler makes the app installable as a PWA (Chrome requires a
// service worker with a fetch listener). We don't cache — just pass through to
// the network — so the dashboard always serves fresh assets from the API.
self.addEventListener('fetch', () => {})

self.addEventListener('notificationclick', (event) => {
    event.notification.close()
    const url = (event.notification.data && event.notification.data.url) || '/admin/orders'
    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
            for (const c of list) {
                if ('focus' in c) { c.navigate(url); return c.focus() }
            }
            if (clients.openWindow) return clients.openWindow(url)
        }),
    )
})
