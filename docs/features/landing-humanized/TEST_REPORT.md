# Test report — landing-humanized (2026-11-17)

Environment: cloud sandbox copy of `apps/xorder-cloud` (landing + packages), Node 22.23.4, pnpm workspace install `--filter @xorder/landing...`. The device shell was unavailable, so nothing was run on the owner's machine.

| Check | Command / method | Result |
|---|---|---|
| Baseline build (before changes) | `pnpm build` in `apps/landing` | `✓ built in 558ms` (existing >500 kB chunk warning) |
| Build after changes | `pnpm build` in `apps/landing` | `✓ built in 880ms` (same chunk-size warning, 547 kB / 169 kB gzip) |
| Layout AR 1440 | Playwright full page | height 8339, scrollWidth 1440 = clientWidth, 53 reveal elements, 0 left hidden, no raw keys |
| Layout AR 390 | Playwright full page | height 13135, scrollWidth 390 = clientWidth, 0 hidden, no raw keys |
| Layout EN 1440 | Playwright full page | height 8463, no overflow; first run showed the whole page mirrored (scoped `:global` bug) — fixed and re-run clean |
| Reduced motion | Playwright `reducedMotion: 'reduce'` | `lp-reveal` not set; only hidden element = lead-form honeypot |
| FAQ | click `#lp-faq-btn-2` | panel 3 `display:block`, others `none` |
| Language toggle | click `.lp-lang` | `dir=ltr`, headline "A digital menu / made for your place" |
| Floating WhatsApp | fixture number 201000000000 | `href=https://wa.me/201000000000` |
| Lead validation | WhatsApp "123" + submit | "Please enter a valid WhatsApp number." |
| Console | Playwright | only `Unexpected token '<'` from `/firebase-config.js`, which the test server did not serve (file not copied) — not a page error |

Not run: API PHPUnit (no API change), real backend, Safari/iOS, Lighthouse.
