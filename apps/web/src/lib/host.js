// Portal context derived from the subdomain the SPA is loaded on.
//   admin.<root>        -> super admin portal
//   <slug>.<root>       -> restaurant admin portal for that slug
//   <root> (no sub)     -> super admin portal (fallback)
// All portals are served at the root path (see vite base).

const RESERVED_SUBS = ['admin', 'www', 'localhost', '127', '0', '::1']

const hostname = window.location.hostname
const parts = hostname.split('.')
const sub = parts.length > 1 ? parts[0] : null

export const restaurantSlug = sub && !RESERVED_SUBS.includes(sub) ? sub : null
export const isSuperAdminHost = restaurantSlug === null

// The shared parent domain, e.g. "localhost" or "tryorder.net".
const rootDomain = parts.length > 1 ? parts.slice(1).join('.') : hostname

function origin(targetHost) {
    const { protocol, port } = window.location
    return `${protocol}//${targetHost}${port ? ':' + port : ''}`
}

export function superAdminUrl(path = '/') {
    return `${origin(`admin.${rootDomain}`)}${path}`
}

export function restaurantUrl(slug, path = '/') {
    return `${origin(`${slug}.${rootDomain}`)}${path}`
}

// Each menu is served on its own subdomain ({slug}.xorder.io/menu), matching
// the backend Restaurant::publicUrl(). This holds in local dev too — *.localhost
// resolves and the backend runs with MENU_DOMAIN set (e.g. demo.localhost:8080).
// The host suffix shown after the slug in the identifier field, e.g.
// ".xorder.io" in production or ".localhost:8080" in local dev.
export const menuHostSuffix = `.${rootDomain}${window.location.port ? ':' + window.location.port : ''}`

// The public menu URL for a slug, matching the backend's canonical public_url.
export function menuUrl(slug) {
    return `${restaurantUrl(slug)}menu`
}

// Tag a menu URL as an owner preview so the API excludes the owner's own visit
// from view analytics. Use ONLY on admin "view my live menu" links — never on
// the customer QR / share URL, which real diners must be counted through.
export function asPreview(url) {
    if (!url) return url
    return url + (url.includes('?') ? '&' : '?') + 'preview=1'
}
