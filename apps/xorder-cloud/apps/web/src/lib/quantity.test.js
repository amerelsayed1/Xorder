import { describe, expect, it } from 'vitest'
import {
    costAt, formatMilli, isWholeMilli, orderTotals, parseQuantity, percentBp, taxWithinBp,
} from './quantity.js'

describe('parseQuantity', () => {
    it('reads thousandths', () => {
        expect(parseQuantity('12.5')).toBe(12500)
        expect(parseQuantity('.5')).toBe(500)
        expect(parseQuantity('3')).toBe(3000)
        expect(parseQuantity('0.001')).toBe(1)
    })
    it('is null for empty and NaN for malformed or too precise', () => {
        expect(parseQuantity('')).toBeNull()
        expect(parseQuantity(undefined)).toBeNull()
        for (const bad of ['1.2345', 'abc', '.', '1.2.3']) expect(parseQuantity(bad)).toBeNaN()
    })
    it('refuses negatives unless allowed', () => {
        expect(parseQuantity('-1')).toBeNaN()
        expect(parseQuantity('-1.5', { allowNegative: true })).toBe(-1500)
    })
    it('folds Arabic digits and the Arabic decimal separator', () => {
        expect(parseQuantity('١٢٫٥')).toBe(12500)
    })
})

describe('formatMilli', () => {
    it('drops trailing zeroes', () => {
        expect(formatMilli(12500)).toBe('12.5')
        expect(formatMilli(2000)).toBe('2')
        expect(formatMilli(-1500)).toBe('-1.5')
        expect(formatMilli(1)).toBe('0.001')
    })
    it('is empty for non-numbers', () => {
        expect(formatMilli(null)).toBe('')
    })
    it('round-trips with parseQuantity', () => {
        for (const q of ['0.1', '0.25', '12.345', '100']) expect(formatMilli(parseQuantity(q))).toBe(q)
    })
})

describe('isWholeMilli', () => {
    it('is true only for whole units', () => {
        expect(isWholeMilli(3000)).toBe(true)
        expect(isWholeMilli(3500)).toBe(false)
    })
})

describe('integer arithmetic', () => {
    it('costAt rounds the line once, half-up', () => {
        expect(costAt(1500, 1001)).toBe(1502) // 1.5 x 10.01 = 15.015
        expect(costAt(1000, 12345)).toBe(12345)
    })
    it('percentBp rounds half-up, away from zero for negatives', () => {
        expect(percentBp(1005, 1000)).toBe(101)
        expect(percentBp(-1005, 1000)).toBe(-101)
    })
    it('taxWithinBp extracts tax already inside a gross amount', () => {
        expect(taxWithinBp(114000, 1400)).toBe(14000) // not 15960
    })
})

describe('orderTotals', () => {
    it('rounds tax per rate, not per line', () => {
        const lines = [
            { quantity_milli: 1000, unit_cost_minor: 333, tax_rate_bp: 1400 },
            { quantity_milli: 1000, unit_cost_minor: 333, tax_rate_bp: 1400 },
            { quantity_milli: 1000, unit_cost_minor: 1000, tax_rate_bp: 0 },
        ]
        // 14% of 666 = 93.24 -> 93 (per-line rounding would give 47 + 47 = 94)
        expect(orderTotals(lines)).toEqual({ subtotal_minor: 1666, tax_minor: 93, total_minor: 1759 })
    })
    it('skips lines with missing numbers', () => {
        expect(orderTotals([{ quantity_milli: 'x', unit_cost_minor: 5 }])).toEqual(
            { subtotal_minor: 0, tax_minor: 0, total_minor: 0 },
        )
    })
})
