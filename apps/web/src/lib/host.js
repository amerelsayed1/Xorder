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
