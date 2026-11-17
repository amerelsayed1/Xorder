# Landing page — humanized redesign (landing-humanized)

Status: implemented in the working tree, not committed, not reviewed, not released · 2026-11-17 · Follows [landing-redesign-easymenu](../landing-redesign-easymenu/FEATURE.md) · Source: owner's design review on the Claude Design canvas "Xorder Landing — Humanized" (references: easy-menu.org motion, menusbee.com marquee/hand-drawn line).

## 1. Summary
A warmer, more human landing page for xorder.io: handwritten accents, a real photo of a person behind a counter, a "day with Xorder" timeline, a cart-to-WhatsApp story, grouped feature list covering the whole platform (not WhatsApp only), scroll-reveal motion and a floating WhatsApp button. Copy is addressed to any food or coffee business, never "مطعمك".

## 2. Owner decisions (2026-11-17)
- **All visible copy lives in code** (`apps/landing/src/i18n/messages.js`, AR + EN). Admin landing-content text fields no longer change the page.
- Still **live from the landing-content API**: pricing plans, industry cards (icon / image / name), demo menus and demo tabs, WhatsApp number + `floating_enabled`, login link, SEO.
- Owner-quote block dropped until a real quote exists; industry cards use the admin image/icon.
- Removed on review: hero badge, hero checklist, hero sub-paragraph, hero stats row, "صُنع بحب" footer line, Plus/Pro tags on features, "العلامات الغذائية المحلية" from the marquee.

## 3. Sections (in order)
Header (transparent logo) · Hero (greeting, "قائمة رقمية على مقاس محلّك", 2 CTAs, photo + order card + demo QR + note) · Business-type marquee · Features (4 groups, 14 capabilities) · Dashboard "يوم عادي" timeline · WhatsApp cart story · hand-drawn divider · Why digital · How it works + live demo · Packages (API) · Businesses (API + "وأكتر من كدا") · FAQ (6, in code) · Lead form (unchanged API) · Closing CTA · Footer · Floating WhatsApp.

## 4. Acceptance criteria
1. `pnpm build` for `@xorder/landing` succeeds.
2. AR (RTL) and EN (LTR) render with no horizontal overflow at 1440 and 390 px; no untranslated `lp.*` keys.
3. Every scroll-revealed element ends visible; with `prefers-reduced-motion` nothing is hidden or animated.
4. Lead form, FAQ accordion, language toggle, demo QR, pricing comparison and analytics events behave as before.
5. Floating WhatsApp shows only when the API gives a number and `floating_enabled` is not false.
6. No third-party font or image host at runtime (fonts and photo are bundled/self-hosted).

## 5. Open items
- Admin-side copy for hero/features/steps/why/FAQ/lead/CTA is now ignored; decide whether to remove those editors or wire them back (**owner decision**).
- `HeroPhone.vue`, `ShowcaseSection.vue`, `DashboardIllus.vue` are no longer imported; delete them (needs file-delete permission on the device).
- The industries list in the admin still contains "العلامات الغذائية المحلية"; remove it in super-admin if it should go from the cards too.
- Industry cards have no photos yet (admin `image` empty in dev data).
