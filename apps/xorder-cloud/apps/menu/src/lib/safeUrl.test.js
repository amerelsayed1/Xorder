import { describe, expect, it } from 'vitest'
import { safeUrl } from './safeUrl.js'

describe('safeUrl', () => {
    it('lets http, https, mailto and tel through unchanged (trimmed)', () => {
        for (const u of ['https://x.io/a?b=1', 'http://x.io', 'mailto:a@b.co', 'tel:+201001234567']) {
            expect(safeUrl(`  ${u} `)).toBe(u)
        }
    })
    it('drops script-capable schemes, whatever the case or padding', () => {
        for (const u of ["javascript:alert(1)", 'JaVaScRiPt:alert(1)', ' data:text/html,<script>', 'vbscript:x', 'file:///etc/passwd']) {
            expect(safeUrl(u)).toBeNull()
        }
    })
    it('drops empty and non-string values', () => {
        for (const v of ['', '   ', null, undefined, 42, {}]) expect(safeUrl(v)).toBeNull()
    })
    it('keeps relative paths (they resolve to the page origin)', () => {
        expect(safeUrl('/menu')).toBe('/menu')
    })
})
