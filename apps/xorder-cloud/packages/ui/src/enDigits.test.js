import { describe, expect, it } from 'vitest'
import { toEnDigits } from './enDigits.js'

describe('toEnDigits', () => {
    it('converts Arabic-Indic and Persian digits to ASCII', () => {
        expect(toEnDigits('٠١٢٣٤٥٦٧٨٩')).toBe('0123456789')
        expect(toEnDigits('۰۱۲۳۴۵۶۷۸۹')).toBe('0123456789')
    })
    it('leaves other text alone', () => {
        expect(toEnDigits('مرحبا 12 abc')).toBe('مرحبا 12 abc')
    })
    it('passes null and undefined through, stringifies numbers', () => {
        expect(toEnDigits(null)).toBeNull()
        expect(toEnDigits(undefined)).toBeUndefined()
        expect(toEnDigits(5)).toBe('5')
    })
})
