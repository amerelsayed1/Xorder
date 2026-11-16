import { describe, expect, it } from 'vitest'
import {
    amountToMinor, applyBp, bpToPercent, currencyExponent, decimalToScaledInt,
    formatMinor, minorToAmount, percentToBp, scaledIntToDecimal,
} from './money.js'

describe('currencyExponent', () => {
    it('is 3 for thousandth-unit currencies, case-insensitively', () => {
        for (const c of ['KWD', 'bhd', 'OMR', 'JOD']) expect(currencyExponent(c)).toBe(3)
    })
    it('is 2 for everything else, including empty', () => {
        for (const c of ['EGP', 'USD', '', null, undefined]) expect(currencyExponent(c)).toBe(2)
    })
})

describe('decimalToScaledInt', () => {
    it('converts without float error (14.55% is 1455, not 1454)', () => {
        expect(percentToBp('14.55')).toBe(1455)
        expect(percentToBp('14.5')).toBe(1450)
        expect(percentToBp('14')).toBe(1400)
    })
    it('returns null for empty and NaN for non-numbers', () => {
        expect(decimalToScaledInt('', 2)).toBeNull()
        expect(decimalToScaledInt(null, 2)).toBeNull()
        for (const bad of ['abc', '.', '1.2.3', '-5', '1e3']) expect(decimalToScaledInt(bad, 2)).toBeNaN()
    })
    it('rounds half-up on the first dropped digit', () => {
        expect(decimalToScaledInt('1.005', 2)).toBe(101)
        expect(decimalToScaledInt('1.004', 2)).toBe(100)
    })
    it('accepts a comma separator and Arabic-Indic digits', () => {
        expect(decimalToScaledInt('١٢,٥', 2)).toBe(1250)
    })
    it('handles a leading-dot amount', () => {
        expect(decimalToScaledInt('.5', 2)).toBe(50)
    })
})

describe('scaledIntToDecimal', () => {
    it('pads and places the point', () => {
        expect(scaledIntToDecimal(1450, 2)).toBe('14.50')
        expect(scaledIntToDecimal(5, 2)).toBe('0.05')
        expect(scaledIntToDecimal(1234567, 3)).toBe('1234.567')
        expect(scaledIntToDecimal(7, 0)).toBe('7')
    })
    it('keeps the sign', () => {
        expect(scaledIntToDecimal(-1450, 2)).toBe('-14.50')
    })
    it('trims trailing zeroes on request', () => {
        expect(bpToPercent(1400)).toBe('14')
        expect(bpToPercent(1450)).toBe('14.5')
    })
    it('returns empty for non-numeric input', () => {
        expect(scaledIntToDecimal(null, 2)).toBe('')
        expect(scaledIntToDecimal('x', 2)).toBe('')
    })
    it('round-trips amounts per currency exponent', () => {
        expect(amountToMinor(minorToAmount(11400, 2), 2)).toBe(11400)
        expect(amountToMinor(minorToAmount(1234567, 3), 3)).toBe(1234567)
    })
})

describe('formatMinor', () => {
    it('returns the bare amount without a currency token', () => {
        expect(formatMinor(59125, 2)).toBe('591.25')
    })
    it('fences the amount in LRI/PDI before the token', () => {
        expect(formatMinor(-59125, 2, 'ج.م')).toBe('⁦-591.25⁩ ج.م')
    })
})

describe('applyBp', () => {
    it('applies basis points rounded half-up', () => {
        expect(applyBp(10000, 1400)).toBe(1400)
        expect(applyBp(1, 5000)).toBe(1)
        expect(applyBp(333, 1400)).toBe(47)
    })
})
