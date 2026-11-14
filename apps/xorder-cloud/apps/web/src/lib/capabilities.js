// The server's TenantCapability values are "<resource>.<action>" pairs
// ('menu.create'). vue-i18n reads dots as key nesting, and the catalogue is
// keyed by resource and action separately so the role editor can render a grid
// — so a human label is composed from the two halves rather than looked up
// whole. One place to do that translation.
export const capabilityParts = (value) => {
    const [resource, action] = String(value).split('.')
    return { resource, action }
}

export const capabilityLabel = (t, value) => {
    const { resource, action } = capabilityParts(value)
    if (!resource || !action) return String(value)
    return `${t(`capres.${resource}`)} — ${t(`capaction.${action}`)}`
}

export const capabilityGroupLabel = (t, group) => t(`capgroup.${group}`)
