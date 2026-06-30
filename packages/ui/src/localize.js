export function pickLocalized(record, field, locale) {
    if (!record) return ''
    const lang = locale === 'ar' ? 'ar' : 'en'
    const primary = `${field}_${lang}`
    const fallback = `${field}_${lang === 'ar' ? 'en' : 'ar'}`

    return record[primary] || record[fallback] || ''
}

export function localizedInitial(record, field, locale, fallback = '?') {
    return (pickLocalized(record, field, locale) || fallback).trim().charAt(0).toUpperCase()
}
