export const OFFERS_CATEGORY_GLYPH = '❉'

const categoryGlyphs = ['◉', '♨', '♢', '◌', '✧', '❋']

export function menuCategoryGlyph(index) {
    return categoryGlyphs[index % categoryGlyphs.length]
}
