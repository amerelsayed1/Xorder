import { computed } from 'vue'
import { useAuth } from '@xorder/api-client/auth.js'

/**
 * Per-action permission flags for one resource, for gating the controls on a
 * list or form screen.
 *
 * Two independent reasons a write control should be hidden, and both are folded
 * in here so no screen has to remember both:
 *
 *   - the account lacks the capability (`tables.create`), or
 *   - the restaurant is read-only (lapsed subscription — `auth.isReadOnly`).
 *
 * `canView` deliberately ignores the read-only state: a lapsed subscription
 * stops writes, it does not blindfold the owner.
 *
 * The server gates the same actions with `can:<resource>.<action>` middleware,
 * so this only decides what is *offered*. Hiding a button is a courtesy, never
 * the boundary — the API still answers 403 to anyone who posts anyway.
 *
 * @param {string} resource e.g. 'tables', 'menu', 'staff'
 */
export function useCaps(resource) {
    const auth = useAuth()
    const can = (action) => auth.can(`${resource}.${action}`)

    return {
        canView: computed(() => can('view')),
        canCreate: computed(() => !auth.isReadOnly && can('create')),
        canUpdate: computed(() => !auth.isReadOnly && can('update')),
        canDelete: computed(() => !auth.isReadOnly && can('delete')),
    }
}
