# Technical plan — landing-redesign-easymenu

Status: **plan approved 2026-10-31; stages 1-6 built, stage 7 partly (see as-built)** · 2026-10-31 · Spec: [FEATURE.md](FEATURE.md) · Verified against xorder-cloud 775bf0f (no uncommitted changes under `apps/landing`; unrelated dirty files in `apps/api` and `apps/web`, left alone) · xorder-pos not touched.

Decision taken 2026-10-31 (open question 1): hero becomes a phone mockup of the real menu; the dashboard moves to its own showcase section.

## 1. Re-verified facts that shape the plan
| Fact | Evidence | Consequence |
|---|---|---|
| Landing content is one JSON row, layered over defaults on every read, so rows saved before a new key exists still resolve it. Lists are taken wholesale from the stored row | `apps/api/app/Models/LandingContent.php:21-65` | **No migration needed** for new keys. Frontend must still use optional chaining |
| `UpdateLandingContentRequest` keeps only validated keys; any key not in `rules()` is dropped on admin save | `apps/api/app/Http/Requests/Admin/UpdateLandingContentRequest.php:20-27` | Every new key must be added there, or the admin's next Save silently erases it |
| `hero.value_points` exists in defaults but is **not validated and not rendered** | `LandingContent.php:100`; no match in `apps/landing/src` or the request | Reuse it for the trust-chip row; add validation. (Admin save currently drops it; defaults come back on read.) |
| `cta` (title, sub, button, whatsapp_label) is validated but the template has **no closing CTA band** | request rules; `LandingView.vue` sections list | Reuse `content.cta` for the final band, no new key |
| Admin editor loads the whole merged document and PUTs it back whole | `apps/web/src/composables/useLandingContent.js:60-80` | New keys round-trip untouched with no admin UI change; editing them in the dashboard is a later, optional item |
| Demo = one `demo.restaurant_slug`; QR from `GET /api/public/restaurants/{slug}/qr`; menu URL `{slug}.<host>/menu` | `LandingView.vue:104-118` | Tabs need a list of slugs: new `demo.tabs` |
| Header nav is a `NAV` array reused by the footer; i18n keys under `landing.*` in `packages/ui/src/i18n/index.js:70` | `LandingView.vue:24-32` | Nav changes affect the footer too; new strings go in both `en` and `ar` there |
| Restaurant owners log in per subdomain; root host is the super-admin fallback; the login screen has a slug identifier field | `apps/web/src/lib/host.js`, `apps/web/src/router/index.js:12` | Where a landing "Login" link should point is **UNVERIFIED** (open question A) |
| No JS test framework or lint scripts exist | `.claude/rules/cloud-laravel-vue.md` | Front-end proof = `pnpm build` + browser checks; API proof = PHPUnit |

## 2. Reuse
`packages/ui` (`Icon`, `XorderLogo`, `theme.css` tokens, Tajawal fonts), existing `--lp-amber`/`--lp-muted` AA tokens, existing lead form and `postLead`, `track()` events, floating WhatsApp, FAQ accordion, pricing cards (all kept as is).

## 3. Impact
- **Repos:** `xorder-cloud` only: `apps/landing` (front end), `apps/api` (content defaults, validation, tests).
- **API contract:** additive keys on `GET /api/public/landing-content` and `PUT /api/admin/landing-content`; no key removed or renamed. POS does not consume it (no client found, **UNVERIFIED**).
- **Schema:** none. **Permissions:** none (`landing.manage` unchanged). **Tenant isolation:** not applicable (public, singleton).
- **Rollout order:** API and landing deploy together from the same push; the landing tolerates missing keys, so either order is safe.
- **Venue models:** copy and demos speak to café, restaurant, food truck and cloud kitchen; no claim on tables, addresses or KDS (known gaps).
- **Risk:** large visual rewrite of a 941-line SFC. Mitigated by extracting components and keeping data, analytics and form logic untouched.

## 4. Stages (each ends buildable; rollback = revert that stage's files)

### Stage 1 — API: additive content keys (backend first)
Files: `apps/api/app/Models/LandingContent.php`, `apps/api/app/Http/Requests/Admin/UpdateLandingContentRequest.php`, `apps/api/tests/Feature/LandingContentTest.php`.
- Defaults (bilingual en/ar, Xorder wording, no invented customers or numbers):
  - `hero.login_label` (bilingual) and `hero.login_link` (string, default empty = Login link hidden until decided).
  - `demo.tabs`: list of `{ key, label{en,ar}, restaurant_slug }`; default one tab reusing the current demo slug.
  - `showcase`: `{ dashboard{title,text}, whatsapp{title,text}, mobile{title,text} }`.
  - `why_us`: `{ title, items[{icon,text}] }` (printed-menu cost, contactless, no reprint) , max 8 items.
- Validation for the new keys plus the existing `hero.value_points` (list max 8, bilingual text); slug rule `alpha_dash`, max 80; login link max 255.
- Tests (extend `LandingContentTest`): legacy row without new keys returns defaults; PUT with new keys persists and returns them; PUT with oversized/invalid slug is 422; keys survive a save (not dropped); public GET unauthenticated still works.
- Proof: `cd apps/xorder-cloud/apps/api && php artisan test --filter LandingContent` then `--filter Lead`, then full suite.

### Stage 2 — Landing structure (no visual change yet)
Files: `apps/landing/src/LandingView.vue` → orchestrator; new `apps/landing/src/components/` (`SiteHeader`, `HeroSection`, `PhoneMock`, `TrustChips`, `BusinessGrid`, `DemoTabs`, `FeatureGrid`, `StepsSection`, `ShowcaseSection`, `WhyUs`, `FinalCta`, keeping Pricing, FAQ, LeadForm, Footer as extracted blocks).
- Move script logic (content load, locale, analytics handlers, lead form, SEO, plan helpers) unchanged into the orchestrator or small `lib/` helpers; props down, events up; keyed `v-for`.
- Proof: `pnpm --filter @xorder/landing build`; page identical in the browser (AC-7, AC-11 regression baseline).

### Stage 3 — Hero + header
- Header: add Login link (only when `hero.login_link` is set), keep CTA, language toggle, drawer; footer keeps using `NAV`.
- Hero: warm gradient, badge, headline, two CTAs, chip row from `hero.value_points`, venue pills, `PhoneMock` with floating chips and QR card (real `demoQrUrl`, hidden if it 404s as today).
- Phone content: screenshots of the real demo menu in `apps/landing/public/img/` (webp, width/height set, lazy), captured with the preview browser from the running menu app; Arabic and English variants. Chosen over an iframe to avoid third-party framing risk, layout shift and extra requests.
- Proof: build; browser at 1440 and 375 px in ar and en; no horizontal scroll (AC-1, AC-2, AC-3).

### Stage 4 — "For every business" grid + features + steps + why-us
- Industries become icon/photo cards (existing `industries.items`); features grid restyled (existing `features.items`); steps restyled; `WhyUs` from `why_us`.
- Proof: build; manual ar/en/mobile; empty list hides its section (AC-4, edge cases).

### Stage 5 — Demo tabs
- `DemoTabs` over `demo.tabs`: switching updates QR, "open live menu" link and `landing_view_demo_clicked`; a tab with an empty slug is not rendered; tablist keyboard support (arrow keys), `aria-selected`.
- Proof: build; manual keyboard and mouse (AC-6, AC-8).

### Stage 6 — Showcases and closing CTA
- `ShowcaseSection`: dashboard screenshot with callouts, WhatsApp order chat mockup (illustrative, drawn in CSS/SVG, labelled as example), mobile screens strip. `FinalCta` from `content.cta`.
- Proof: build; manual (AC-1, AC-2).

### Stage 7 — Polish and verification
- `prefers-reduced-motion`, contrast pass with the existing AA tokens, focus rings, image weights, bundle size note against the current `dist` (record the number before Stage 2 as the baseline), console clean.
- Proof: `pnpm build` output; preview in both locales and at 375 px; contrast spot-check; network tab for analytics events (AC-8..AC-11).

## 5. Test and verification summary
| AC | Proof |
|---|---|
| AC-4, AC-5 | PHPUnit `LandingContentTest` (Stage 1) |
| AC-7 | existing `LeadTest` + manual submit |
| AC-10 | `pnpm build` output |
| AC-1, 2, 3, 6, 8, 9, 11 | manual in the preview browser (no JS test framework; stated plainly in the report) |

PostgreSQL behavior: not involved (no schema or SQL change).

## 6. Approvals needed before building
1. Content-contract change (additive keys in `LandingContent` defaults and `UpdateLandingContentRequest`) — Stage 1.
2. New image assets (screenshots) added to `apps/landing/public/img/`.
3. Component extraction in `apps/landing` (a structural rewrite of the SFC, no new dependencies).
4. Nothing is committed or pushed; a push to `xorder-cloud` `main` deploys to production and needs `/release-check` and the owner's go.

## 7. Open questions
- **A. Login link target:** root host falls back to the super-admin portal and owners log in on `<slug>.xorder.io`. Which URL should "Login" open? Default: hidden until set via `hero.login_link`.
- **B. Clients strip:** omitted until real, permitted logos exist.
- **C. Demo tabs:** which demo restaurants exist for café, food truck, cloud kitchen? Default: one tab with the current demo slug.
- **D. Screenshots vs live iframe** for the phone: plan uses screenshots; confirm.
- **E. Editing new sections in the dashboard Settings UI** (`apps/web/src/pages/admin/settings/*`): out of this plan; defaults are used until a follow-up.

## 8. As-built (2026-10-31) and deviations from the plan
Done: Stage 1 (API keys `hero.login_label/login_link/value_points`, `demo.tabs`, `showcase`, `why_us`; validation lenient `nullable`, tests), `landing.*` i18n keys en+ar, hero (phone mockup with floating chips and QR card, trust chips from `hero.value_points`, venue pills), header/drawer Login link (hidden when `login_link` empty), demo tabs (shown only with ≥ 2 tabs), dashboard and WhatsApp showcases, "why go digital", closing CTA band from `content.cta`.
Deviations:
- **No full component extraction.** Only new parts are components (`HeroPhone`, `ShowcaseSection`, `DashboardIllus`); existing sections stay in `LandingView.vue` to keep the diff small and avoid regressions in pricing/FAQ/lead form.
- **Phone is a drawn mockup (emoji + bars), not screenshots**: no real screenshots were captured, so no new image assets were added. Real screenshots remain a follow-up.
- **No separate mobile-screens carousel** and **no clients strip** (no real assets/logos).
- The "for every business" grid keeps the existing `industries` chips styling; restyle not done.
- Admin Settings UI for the new keys not built (open question E); defaults are used.
- `.claude/launch.json` (workspace root, local tooling) gained a `landing` entry to preview the page.
Environment: `pnpm install --frozen-lockfile` was run with the owner's approval to get the arm64 Rolldown binding; lockfile unchanged.
