# Test plan — landing-humanized
1. `pnpm --filter @xorder/landing build`.
2. Serve the build with a landing-content fixture (shape copied from the local dev API: 3 plans, 7 industries, WhatsApp number) and run Playwright: AR 1440, AR 390, EN 1440 full-page screenshots; check scroll width = client width, no `.lp-rv` left at opacity 0 after scrolling, no raw `lp.*` keys.
3. Reduced motion: no `html.lp-reveal`, no hidden element (except the lead honeypot).
4. Interactions: FAQ item 3 opens; language toggle flips to LTR + English headline; floating WhatsApp href = `https://wa.me/<number>`; invalid WhatsApp number shows the validation message without a request.
5. Not covered (owner/CI): real API in dev (`pnpm dev:landing`), Safari/iOS, Lighthouse, analytics events in GA4.
