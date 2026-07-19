// Locale-aware currency token shown next to prices.
//
// Egypt is displayed as "EGP" in English and "ج٫م" in Arabic; other currencies
// keep whatever symbol the API resolved. Presentation-only — the stored value
// is always the ISO code.
export function currencyLabel(code, locale, fallbackSymbol = '') {
    if (code === 'EGP') return locale === 'ar' ? 'ج٫م' : 'EGP'
    return fallbackSymbol || code || ''
}
