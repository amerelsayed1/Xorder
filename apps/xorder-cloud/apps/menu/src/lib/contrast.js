// Text colour that stays readable ON a tenant's brand colour. A fixed white
// fails WCAG AA on light or amber brands (the default #f59e0b is ~2:1), so pick
// white or a dark ink, whichever has the higher contrast. Unparseable colours
// (named colours, hsl()) keep white, the previous behaviour.
export function readableOn(color) {
    const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(color).trim())
    if (!m) return '#ffffff'
    const hex = m[1].length === 3 ? [...m[1]].map((c) => c + c).join('') : m[1]
    const lin = [0, 2, 4].map((i) => {
        const v = parseInt(hex.slice(i, i + 2), 16) / 255
        return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
    })
    const lum = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    const ink = '#1f1a14'
    const inkLum = 0.0108 // relative luminance of #1f1a14
    const whiteContrast = 1.05 / (lum + 0.05)
    const inkContrast = (lum + 0.05) / (inkLum + 0.05)
    return whiteContrast >= inkContrast ? '#ffffff' : ink
}
