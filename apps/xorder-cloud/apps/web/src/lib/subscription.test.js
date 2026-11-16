import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { daysUntil, todayIn } from './subscription.js'

beforeEach(() => {
    vi.useFakeTimers()
    // 23:30 UTC on 2026-11-16 is already 01:30 on the 17th in Cairo (UTC+2).
    vi.setSystemTime(new Date('2026-11-16T23:30:00Z'))
})
afterEach(() => vi.useRealTimers())

describe('todayIn', () => {
    it("uses the restaurant's own day, not the browser's", () => {
        expect(todayIn('UTC')).toBe('2026-11-16')
        expect(todayIn('Africa/Cairo')).toBe('2026-11-17')
    })
    it('falls back to a valid date for a bad zone', () => {
        expect(todayIn('Not/AZone')).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    })
})

describe('daysUntil', () => {
    it('counts whole calendar days in the restaurant zone', () => {
        expect(daysUntil('2026-11-20', 'UTC')).toBe(4)
        expect(daysUntil('2026-11-20', 'Africa/Cairo')).toBe(3)
    })
    it('is negative once past and zero on the day', () => {
        expect(daysUntil('2026-11-16', 'UTC')).toBe(0)
        expect(daysUntil('2026-11-10', 'UTC')).toBe(-6)
    })
    it('is null with no or unreadable end date', () => {
        expect(daysUntil(null, 'UTC')).toBeNull()
        expect(daysUntil('garbage', 'UTC')).toBeNull()
    })
})
