# Technical — landing-humanized

Verified against: workspace files staged 2026-11-17 (git revision **UNVERIFIED**: the device shell was unavailable, so `git rev-parse`/`git status` could not be run).

## Changed files (apps/xorder-cloud/apps/landing)
| File | Change |
|---|---|
| `src/LandingView.vue` | Template + styles rewritten; script keeps content load, scroll-spy, demo tabs/QR, WhatsApp link, plan comparison, lead form and SEO. Removed: `XorderLogo`, `HeroPhone`, `ShowcaseSection`, `heroChips`, `whyItems`, `heroWa`, `enabledFaqs`. Added: `FEATURE_GROUPS`, `industries`, `vReveal`. |
| `src/i18n/messages.js` (new) | All page copy, AR + EN, namespace `lp`. Lists read with `tm()` + `rt()`. |
| `src/main.js` | Merges `messages.js` into the shared i18n instance (`mergeLocaleMessage`); `packages/ui/src/i18n` untouched. |
| `src/lib/reveal.js` (new) | `v-reveal` directive: IntersectionObserver adds `.is-in`; hidden start state only after JS adds `html.lp-reveal`; skipped under reduced motion. |
| `src/components/HeroVisual.vue` (new) | Photo, order card, demo QR card, handwritten note. |
| `src/components/WhatsappStory.vue` (new) | Cart → arrow → WhatsApp message loop + struck-through questions. |
| `src/components/WaFloat.vue` (new) | Floating WhatsApp button (entrance, rings, wiggle, tooltip). |
| `src/app.css` | Aref Ruqaa `@font-face` (self-hosted), `.lp-hand`, reveal keyframes, shared `.lp-eyebrow/.lp-h2/.lp-sub`. |
| `src/assets/xorder-logo.png` (new) | Transparent copy of `packages/ui/src/assets/xorder_full_logo.png` (shared file has a white background; left unchanged). |
| `src/assets/hero-barista.jpg` (new) | Unsplash photo by Brooke Cagle (Unsplash License, free commercial use, no attribution required), cropped 840×1000. |
| `public/fonts/aref-ruqaa-400-{arabic,latin}.woff2` (new), `public/fonts/LICENSE.txt` | Aref Ruqaa, SIL OFL 1.1 (copyright line added). |

## Contract / data impact
None. Reads the same `GET /api/public/landing-content`; no API, schema, permission or POS change. Fields now unused by the page (still served): `hero.title/sub/badge/value_points/cta/secondary`, `proof`, `features`, `showcase`, `why_us`, `steps`, `faq`, `lead_form`, `cta`, `footer`, `pricing.title/sub/popular_label/choose_label`, `industries.title/sub`.

## Notes
- Reveal animates the standalone `translate` property so card hover `transform` still works; the WhatsApp button uses `scale` on hover for the same reason.
- Vue scoped `:global(x) y` swallows the whole rule (it flipped the page in LTR during testing); RTL/LTR overrides are written as plain `[dir='ltr'] .x`.
