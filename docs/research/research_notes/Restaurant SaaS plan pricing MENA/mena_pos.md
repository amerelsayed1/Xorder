# Restaurant POS pricing and plan packaging in Egypt and MENA (researched 2026-11-04)

Conventions used throughout:
- "Seen 2026-11-04" means the page was fetched live on that date. Search-snippet-only or aggregator figures are marked **UNVERIFIED**.
- FX: **SAR→USD at 3.75 SAR = 1 USD** (fixed peg). **EGP→USD at 52.46 EGP = 1 USD**, the CBE selling rate in Almal News' central-bank table of 10 Oct 2026 ([Almal News](https://almalnews.com/2140232/خريطة-أسعار-العملات-اليوم-السبت-10-10/)). The EGP rate is volatile and sources conflict. Dostor reported the dollar "below 57 EGP" on 27 Oct 2026 ([Dostor](https://dostor.org/5751062)), and at 57 every EGP→USD figure below would be about 8% lower. No CBE figure dated November 2026 was found.
- Every price is excl. VAT unless stated. Egypt VAT is 14%, KSA 15% (general knowledge, not re-verified here).

## Q1. Tier names, prices, and billing basis (per branch, device or account) by vendor

### Takeaway
Pricing splits into two camps. Foodics and Rewaa sell **per-branch bundles**, roughly USD 55–205 per branch per month. Foodics Egypt bundles cost about EGP 2,850–3,960 (USD 54–75) per month. Egyptian local and accounting players (Daftra, Solo POS) sell **per-account plans** at EGP 490–3,000 (USD 9–57) per month, then charge separately for extra branches, POS devices and users. Odoo and Syrve/iiko are per user. Loyverse is free, with per-store and per-employee add-ons.

### Cited Findings

**Foodics: Egypt (primary, seen 2026-11-04)**
- Two bundles are shown in EGP per month. **Basic Bundle: EGP 2,848.95 and EGP 3,019.89/mo (≈ USD 54.31 / 57.57). Advanced Bundle: EGP 3,733.67 and EGP 3,957.69/mo (≈ USD 71.17 / 75.44).** The toggle is labelled Quarterly/Yearly and "Billed Annually". The page does not say which of the two figures is the yearly rate and which is the quarterly rate. The lower figure is probably yearly (inference). — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)
- The Egypt page shows **no Starter bundle**, only Basic and Advanced. — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)
- **UNVERIFIED:** a third-party GitHub repo claims "Foodics raised Egypt prices 15–17% in 2026 and dropped its entry tier". The repo's own notes say this comes from an internal record, not a public list. — [devyapos issue #66](https://github.com/eng-AhmedMahmoud/devyapos/issues/66)
- The Egypt page does not say whether the price is per branch or per device. The KSA page says per branch (below). — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)

**Foodics: KSA (primary, seen 2026-11-04)**

| Bundle | Monthly | Annual (per month) | Annual total | "Daily" | USD (monthly / annual per month) |
|---|---|---|---|---|---|
| Starter | SAR 248 | SAR 228 | SAR 2,736 | 12.00 | 66.13 / 60.80 |
| Basic | SAR 450 | SAR 414 | SAR 4,968 | 19.00 | 120.00 / 110.40 |
| Advanced | SAR 765 | SAR 704 | SAR 8,448 | 29.00 | 204.00 / 187.73 |

- The page says the price is "Per branch, covered by your daily sales" and "No upfront payments. Hardware Included." The final quote is "built just for you based on your ideal hardware and software". — [Foodics KSA pricing](https://www.foodics.com/pricing/)
- Annual billing is about **8% cheaper** than monthly (228/248 = 0.92). This is calculated from the figures above.
- **Conflicting or stale:** a search-engine cache about 387 days old showed KSA Basic at SAR 801 monthly / 742 annual and Advanced at SAR 1,224 / 1,133, plus a lower set at SAR 612/567 and 936/867. That suggests KSA prices were cut or restructured during 2025–26. **UNVERIFIED** (cache only). — [Foodics KSA pricing (search cache)](https://www.foodics.com/pricing/)
- Third-party figures also disagree. TrustRadius lists Starter SAR 219, Basic SAR 409 and Advanced SAR 675 per month. One review gives a SAR 1,500 implementation fee. **UNVERIFIED.** — [TrustRadius](https://www.trustradius.com/products/foodics/pricing); [lkwjd review](https://lkwjd.com/foodics-review)
- POSRocket: no current pricing was found. It was acquired by Foodics, and no separate POSRocket price list surfaced in searches. Gap.

**Rewaa: KSA, retail-first but also sold to F&B (primary, seen 2026-11-04; prices excl. VAT)**

| Plan | Term | SAR/mo | USD/mo | Branches | Registers per branch | Extra users per branch |
|---|---|---|---|---|---|---|
| Starter (الانطلاقة) | 1 yr, paid annually | 275 | 73.33 | 1 | 1 | 1 |
| Starter | 2 yr | 247 | 65.87 | 1 | 1 | 2 |
| Growth (النمو) | 1 yr | 367 | 97.87 | 1 | 2 | 2 |
| Growth | 2 yr | 330 | 88.00 | 2 | 2 | 2 |
| Premium (التميز) | 1 yr | 708 | 188.80 | 2 | 3 | 3 |

- **No monthly billing.** The shortest term is one year, paid annually, and a 2-year term gets about 10% off. — [Rewaa pricing](https://rewaa.com/pricing)

**Daftra: Egypt-facing plans page in EGP (primary, seen 2026-11-04; the page rendered in ج.م)**

| Plan | Monthly billing | Yearly billing (per month) | Yearly total | USD (monthly / yearly per month) |
|---|---|---|---|---|
| Basic (الأساسية) | EGP 733.00 | EGP 489.50 | EGP 5,874 | 13.97 / 9.33 |
| Advanced (المتقدمة) | EGP 1,225.00 | EGP 977.58 | EGP 11,731 | 23.35 / 18.63 |
| Comprehensive (الشاملة) | EGP 2,448.00 | EGP 1,960.00 | EGP 23,520 | 46.66 / 37.36 |

- Plans are capped by invoices per month (100 / 500 / unlimited), customers (100 / 300 / unlimited) and warehouses (1 / 3 / 5). The page lists "unlimited POS devices" for cloud POS, while **offline POS is a counted, paid unit**. — [Daftra plans](https://www.daftra.com/plans)
- Another search snippet says hardware-based offline POS is available "on the Premium plan only", with transactions stored locally and synced once online. — [Daftra plans (snippet)](https://www.daftra.com/plans)
- This confirms the "Daftra starts at EGP 489.50" claim in [devyapos issue #66](https://github.com/eng-AhmedMahmoud/devyapos/issues/66).

**Solo POS: Egyptian restaurant and café POS (primary, seen 2026-11-04)**

| Plan | EGP/mo | USD/mo | Key contents |
|---|---|---|---|
| Basic | 499 | 9.51 | Full POS, online and offline, KDS, partial reports (daily log, cash drawer) |
| Pro | 999 | 19.04 | + full reports, inventory, suppliers, staff and attendance, CRM, tables, web/app dashboard |
| Mega ("most requested") | 1,499 | 28.57 | + online ordering (tables, delivery, pickup), delivery companies with per-channel pricing, waiter app, delivery driver and supervisor apps, advanced inventory app, AI |
| Empire | 2,999 | 57.17 | + multi-branch (1 extra branch free), permissions, approval workflows, accounting, HR |

- Discounts are 5% quarterly, 10% semi-annual and 20% annual. Each price appears twice on the page, probably a struck-through original, but this is unclear. The page does not state per-device pricing. — [Solo POS](https://www.getsolopos.com/)

**Odoo POS (Shop and Restaurant): global list price (primary, seen 2026-11-04)**
- Plans are One App Free at USD 0, Standard at **USD 8.95 / 11.20 per user/month**, and Custom at **USD 16.40 / 20.90 per user/month**. Custom adds Studio, multi-company and the external API. Light User is USD 2.90. The asterisked lower price is a 12-month discount for initial users, and the page does not cleanly label which price is yearly and which is monthly. POS Shop and POS Restaurant are included in the "all apps" fee, and **no per-terminal fee** is listed. — [Odoo pricing](https://www.odoo.com/pricing)
- An Egyptian partner blog (2B Cloud Solutions, dated 11 Mar 2026) quotes Standard at **EGP 1,200–1,500 per user/month (USD 22.87–28.59)** and Custom at **EGP 1,800–2,500 (USD 34.31–47.66)**, with 15–20% off for annual billing. These figures are **2–3× Odoo's USD list**, so they are a partner's inflated or bundled figures, or simply inaccurate. Treat them as **conflicting with the primary source**. — [2b-cs blog](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)
- The same partner gives first-year implementation bundles (software, implementation, training, ETA): **EGP 40k–70k for 1–2 terminals (USD 762–1,334), EGP 90k–150k for 3–5 terminals, and EGP 180k–300k for 6–10 terminal restaurant chains (USD 3,431–5,719)**. Ongoing cost is about 30–40% of the initial implementation per year. — [2b-cs blog](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)
- Other partner and aggregator estimates: a basic Odoo deployment in Egypt costs EGP 125k–350k, and ETA compliance setup adds EGP 30k–80k. **UNVERIFIED** (secondary). — [azdan](https://www.azdan.com/blog/erp-companies-egypt); [buildn.tech](https://buildn.tech/en/blog/erp-implementation-cost-egypt-2026)

**Loyverse (primary, seen 2026-11-04; USD, excl. tax)**
- The POS is free. Also free: 31-day sales analytics, essential inventory, a loyalty program, customer display, **kitchen display**, multi-store management and integrations. — [Loyverse pricing](https://loyverse.com/pricing)
- Paid add-ons: **unlimited sales history at USD 5/mo or USD 50/yr per store; employee management at USD 5/mo or USD 50/yr per employee; advanced inventory at USD 25/mo or USD 250/yr per store**. Annual billing saves "2 months", about 17%. — [Loyverse pricing](https://loyverse.com/pricing)

**Qoyod: KSA accounting with a POS add-on (all UNVERIFIED; qoyod.com/pricing returned 404)**
- One review lists Basic at SAR 120 (USD 32), Pro at SAR 180 (USD 48) and Advanced at SAR 330 (USD 88) per month, Enterprise at a custom price, and **POS at SAR 50 (USD 13.33) per user/month as an add-on**. — [treasurymetric](https://treasurymetric.com/review/qoyod/)
- Another source gives Pro at SAR 180 monthly or SAR 150 on annual billing, and Pro plus 1 POS user at SAR 230/mo. — [sif.xrero guide](https://sif.xrero.com/en/guides/accounting-software-prices-saudi-arabia/)

**Marn: KSA (UNVERIFIED; no public price list)**
- No published plans page was found; prospects go through a sales form. One aggregator lists Starter USD 15, Basic USD 25 and Advance USD 40, while the same site elsewhere says "quotation based". — [SaaSWorthy](https://www.saasworthy.com/product/marn-pos/pricing); [SpotSaaS](https://www.spotsaas.com/product/marn-pos/pricing); [Snad comparison](https://www.snad.io/en/blog/afdal-barnamaj-nuqat-bay-mahalat-tajzia-saudi)

**Sapaad: UAE-based, sold across MENA (UNVERIFIED; aggregators only)**
- Capterra shows from USD 39.99/mo. TrustRadius shows tiers by outlet count: USD 58.99 for 1 outlet, USD 155.99 for 3 and USD 234.99 for 5. ITQlick shows about USD 40 per user/month. — [Capterra](https://www.capterra.com/p/143844/Sapaad/pricing/); [TrustRadius](https://www.trustradius.com/products/sapaad/pricing); [ITQlick](https://www.itqlick.com/sapaad/pricing)

**Syrve / iiko (UNVERIFIED; aggregators only)**
- Syrve: Basic, Professional and Enterprise at £49 / £69 / £99 per user/month on Capterra, and USD 49 / 69 / 99 on GetApp. — [Capterra](https://www.capterra.com/p/10022785/Syrve/); [GetApp](https://www.getapp.com/retail-consumer-services-software/a/syrve/)
- iiko: from USD 79 per user/month. — [ITQlick](https://www.itqlick.com/iiko/pricing)

**Other Egyptian local signals (UNVERIFIED, secondary)**
- DineCore guide: a full restaurant system in Egypt "starts from EGP 15,000/year" (about USD 286). — [DineCore blog](https://dinecore.wizzora.app/blog/restaurant-opening-cost-egypt)
- Unnamed "local cashier software lists at EGP 199" per branch. — [devyapos issue #66](https://github.com/eng-AhmedMahmoud/devyapos/issues/66)
- Egyptian vendors found but not priced (no prices were retrieved): Be Creative cloud cashier ([becreativesystem](https://becreativesystem.com/cashier-program/)), Kashier app ([kashierapp](https://kashierapp.com/%D8%A8%D8%B1%D9%86%D8%A7%D9%85%D8%AC-%D9%83%D8%A7%D8%B4%D9%8A%D8%B1-%D9%85%D8%B7%D8%B9%D9%85)) and Alcashier ([alcashier](https://alcashier.com/%D8%A3%D8%B3%D8%B9%D8%A7%D8%B1-%D8%A8%D8%B1%D8%A7%D9%85%D8%AC-%D8%A7%D9%84%D9%83%D8%A7%D8%B4%D9%8A%D8%B1/)).

### Inferences
- **The Egypt price ladder** (USD per month per branch or account, at 52.46): Solo POS 9.5–57, Daftra 9.3–47, Foodics Egypt 54–75, Odoo about 9–21 per user at list but with heavy partner implementation costs. Foodics Egypt Basic costs about **5.7× Solo POS Basic** and about **2.9× Solo POS Pro** (inventory and suppliers). Calculated.
- **Foodics charges Egypt less in USD than KSA.** Egypt Basic is about USD 54–58 against KSA Basic at USD 110–120, so it localises the price to about 50% of KSA. Calculated from the two primary pages.
- **The dominant MENA packaging unit is the branch** (Foodics, Rewaa), with registers and users as capped allowances inside the branch. Per-device licensing appears only as an add-on unit: Daftra offline POS at EGP 490–637 per month, Rewaa extra register at SAR 149–249. A per-device desktop licence like Xorder's is therefore unusual. It would need to be priced so that a typical café with one or two tills lands near the per-branch competitors.
- **Daftra's offline POS** at EGP 490/mo per device (yearly billing) is the closest local analogue to Xorder's per-device offline desktop licence, so it is a useful anchor.

### Gaps
- No primary price was found for Marn, Sapaad, Syrve/iiko, POSRocket, Qoyod (404), Edara, Bluepos or Omega. Searches for those Egyptian brands returned nothing priced, and they were not searched individually because of the tool budget.
- Foodics Egypt does not say whether the bundle price is per branch or per device, or which of its two prices is the yearly one.

## Q2. What each tier includes, and which items are paid add-ons with prices

### Takeaway
Inventory and purchasing sit in the middle tier everywhere: Foodics Basic, Solo Pro, and Rewaa from Starter. Delivery-aggregator integration, loyalty, an online-ordering website, BI and the API sit in the top tier or are add-ons. Accounting is usually a separate product or a top-tier feature. Published add-on prices are rare outside Rewaa, Daftra and Loyverse.

### Cited Findings
- **Foodics Egypt Basic:** cloud POS, menu management, customer module, dashboards, reporting, **inventory**, table management, Foodics Marketplace, timed events, coupons, delivery zones, gift cards, promotions. **Advanced adds:** loyalty, API integration, Foodics Online website, **delivery aggregators**, Foodics BI. Add-ons are listed but **unpriced**: Web Cashier, **Digital Receipts**, Cloud Kitchen (multi-brand) and others. Foodics Accounting is a separate product. — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)
- **Foodics KSA:** Starter covers the cloud cashier, menu, customers, dashboards, reporting, discounts, and a customer display ("free with Pay"). Basic adds timed events, coupons, promotions, **inventory management (costing and purchasing)**, marketplace, tables and gift cards. Advanced adds website, Foodics AI & BI, and an API private token. KDS and Accounting are separate products, not bundle features. — [Foodics KSA pricing](https://www.foodics.com/pricing/)
- **Foodics delivery-integration cost** is estimated at SAR 200–400/month per platform, and hardware and extra modules cost extra. **UNVERIFIED** (review). — [lkwjd review](https://lkwjd.com/foodics-review)
- **Rewaa Starter** includes sales and customers, products and inventory, **purchases and suppliers**, expenses, reports, ZATCA phase 2, limited AI invoice reader, and the cashier app. **Accounting and Boonat loyalty are paid add-ons** on Starter 1-yr and are included from Starter 2-yr. Growth adds multi-printer, unlimited AI reader and a free extra register. Growth 2-yr adds e-commerce store integration, a free extra branch and a free device set. — [Rewaa pricing](https://rewaa.com/pricing)
- **Rewaa add-on prices (SAR; the billing period is not labelled on the page, UNVERIFIED whether monthly or yearly):**

| Plan | Extra branch | Extra register | Extra user |
|---|---|---|---|
| Starter 2-yr | 3,198 (USD 852.80) | 249 (USD 66.40) | 149 (USD 39.73) |
| Growth 1-yr | 1,299 (USD 346.40) | 199 (USD 53.07) | 149 (USD 39.73) |
| Growth 2-yr | 1,818.6 (USD 484.96) | 199 (USD 53.07) | 99 (USD 26.40) |
| Premium | 899 (USD 239.73) | 149 (USD 39.73) | 79 (USD 21.07) |

  Device discounts are 70% off the new-customer device set on Starter 2-yr, 15% off extra devices on Growth, and 20% on Premium. — [Rewaa pricing](https://rewaa.com/pricing)
- **Daftra add-ons (EGP per unit per month, monthly / yearly billing):**

| Add-on | Monthly billing | Yearly billing | USD (monthly / yearly) |
|---|---|---|---|
| Extra user | 392 | 294 | 7.47 / 5.60 |
| Extra branch | 1,293.60 | 980 | 24.66 / 18.68 |
| Extra offline POS (same figures also in the warehouse row, ambiguous) | 637 | 490 | 12.14 / 9.34 |
| Extra HR employee | 129.36 | 107.80 | — |
| Storage per GB | 24.50 | 24.50 | — |

  — [Daftra plans](https://www.daftra.com/plans)
- **Solo POS** puts KDS in its cheapest tier (Basic). Inventory, suppliers and CRM are in Pro. Online ordering, delivery companies and waiter and driver apps are in Mega. Multi-branch, accounting and HR are in Empire. The FAQ says items have recipes that deduct ingredients, but does not assign recipes to a tier. — [Solo POS](https://www.getsolopos.com/)
- **Loyverse** gives KDS, loyalty, multi-store and integrations away free, and monetises history, employees and advanced inventory (purchase orders, suppliers and similar) as per-store or per-employee add-ons. — [Loyverse pricing](https://loyverse.com/pricing)
- **Odoo** includes POS Restaurant, Inventory, Purchase and Accounting in Standard, with no per-terminal fee. Multi-company and the API need Custom. — [Odoo pricing](https://www.odoo.com/pricing)
- **Qoyod** sells POS as a SAR 50 per user/month add-on on top of an accounting plan. **UNVERIFIED.** — [treasurymetric](https://treasurymetric.com/review/qoyod/)

### Inferences
- The gating pattern Xorder would follow if it matched the market:
  - Entry tier: POS, menu and reports, sometimes KDS (Solo, Loyverse).
  - Middle tier: inventory, purchasing, suppliers, tables.
  - Top tier: aggregators, online ordering, loyalty, BI, API, multi-branch, accounting.
- Inventory, purchasing and suppliers are clearly a mid-tier upsell lever in this market. That fits selling Xorder's cloud back office as the paid upgrade over a basic POS licence.

### Gaps
- Explicit add-on prices were not found for Foodics (aggregators, digital receipts, KDS, extra cashier device), Marn or Sapaad.
- Recipe and BOM placement per tier is not stated by Foodics, Rewaa or Daftra.

## Q3. Egypt Tax Authority (ETA) e-receipt and e-invoice: who includes it, and at what cost

### Takeaway
No surveyed vendor publishes a priced ETA e-receipt add-on on its own pricing page. Foodics Egypt lists "Digital Receipts" as an unpriced add-on. Odoo relies on paid third-party or partner modules costing about USD 350–850 one-time plus partner setup. Hardware or fiscal-device routes cost EGP 4k–25k per terminal. Built-in, no-extra-fee ETA e-receipt support would be a differentiator, but this is an inference.

### Cited Findings
- Decision 281/2024 extends the e-receipt requirement to restaurant bills and other B2C transactions. — [2b-cs B2C](https://www.2b-cs.com/blog/2b-1/egypt-b2c-invoicing-48)
- **Foodics Egypt:** "Digital Receipts" is an add-on on both bundles, with no price shown. The page does not mention ETA by name. — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)
- **Odoo:** third-party ETA e-receipt connectors include Qsys IT at about USD 455 on the Odoo Apps store, and ECOSIRE's Egypt ETA module at USD 349, which also requires a USD 499 core module. Native Enterprise `l10n_eg_edi` covers the ETA e-invoice. The POS e-receipt is listed as "Custom", so it is **not standard**. — [Odoo Apps search](https://apps.odoo.com/apps/modules/browse?search=POS+Receipt); [ECOSIRE docs](https://docs.ecosire.com/odoo-modules/egypt-eta-einvoicing); [ECOSIRE guide](https://ecosire.com/blog/odoo-egypt-localization-guide-2026); [Flexigo](https://flexigotech.com/egypt-eta-odoo-en.html)
- The Egyptian Odoo partner bundles ETA e-receipt integration into its implementation fee (EGP 40k–300k) and quotes an **ETA-certified fiscal device at EGP 15,000–25,000 per terminal (USD 286–477)**. — [2b-cs blog](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)
- E-receipt-capable POS devices in Egypt cost from EGP 4,000 to 19,000+ according to Pioneers (EGP 4,500–7,000 for economy models in another of its posts) and EGP 3,000–15,000 according to eDariba. eDariba also offers a device-free e-receipt subscription at **EGP 300/month (USD 5.72)**, and notes that e-seal activation costs extra. **UNVERIFIED** (vendor blogs). — [Pioneers](https://pioneers-solutions.com/blog-best-pos-electronic-receipts-egypt); [Pioneers price](https://pioneers-solutions.com/blog-electronic-receipt-device-price-egypt); [eDariba](https://edariba.com/blog/%D8%B3%D8%B9%D8%B1-%D8%AC%D9%87%D8%A7%D8%B2-%D9%86%D9%82%D8%A7%D8%B7-%D8%A7%D9%84%D8%A8%D9%8A%D8%B9/)
- **Daftra** has an Egypt e-invoicing product page with a 14-day trial. Its plans page only mentions Saudi phase 2 compliance, and no Egypt e-receipt price per plan was found. — [Daftra Egypt e-invoice](https://www.daftra.com/en/egy-electronic-invoice); [Daftra plans](https://www.daftra.com/plans)
- **Solo POS** does not mention ETA anywhere on its page. — [Solo POS](https://www.getsolopos.com/)
- **KSA vendors** (Rewaa all plans, Foodics) include ZATCA phase 2 in the base price. This is the KSA analogue, not ETA. — [Rewaa pricing](https://rewaa.com/pricing)

### Inferences
- The market reference for a standalone e-receipt service is about EGP 300/month (eDariba), against about USD 350–850 one-time for Odoo modules. If Xorder charges for ETA, a per-branch monthly fee in the low hundreds of EGP would be within the market range. Including it in a mid tier would undercut Odoo and partner pricing.

### Gaps
- Whether Foodics Egypt's "Digital Receipts" add-on is ETA e-receipt submission, and what it costs, was not confirmed.
- No primary ETA fee was found for Daftra, Edara or other Egyptian local vendors. Government-side costs (e-seal or e-signature token, onboarding) were not researched with a primary source.

## Q4. Free trials, annual discounts, setup and onboarding fees, hardware

### Takeaway
A 14-day free trial with no credit card is the norm (Daftra, Solo POS, Loyverse add-ons). Annual discounts range from about 8% (Foodics KSA) through about 17–20% (Loyverse, Solo) to about 33% (Daftra). Rewaa only sells annual or 2-year terms. Foodics KSA advertises "hardware included, no upfront payments". Setup fees are rarely published.

### Cited Findings
- **Trials:**
  - Daftra: 14 days, no credit card, no setup. — [Daftra plans](https://www.daftra.com/plans)
  - Solo POS: 14 days, no credit card, limited to one Solo app during the trial. — [Solo POS](https://www.getsolopos.com/)
  - Loyverse: 14 days per paid add-on, no card. — [Loyverse pricing](https://loyverse.com/pricing)
  - Rewaa: no trial terms found on the pricing page. — [Rewaa pricing](https://rewaa.com/pricing)
- **Annual and term discounts:**
  - Foodics KSA: about 8% (SAR 228 vs 248). — [Foodics KSA](https://www.foodics.com/pricing/)
  - Daftra: "up to 30%" claimed, about 33% calculated on Basic (489.50 vs 733). — [Daftra plans](https://www.daftra.com/plans)
  - Solo POS: 5% quarterly, 10% semi-annual, 20% annual. — [Solo POS](https://www.getsolopos.com/)
  - Loyverse: "save 2 months", about 17%. — [Loyverse](https://loyverse.com/pricing)
  - Rewaa: annual only; 2-year about 10% off. — [Rewaa](https://rewaa.com/pricing)
  - Odoo: a first-12-months discount for initial users. — [Odoo pricing](https://www.odoo.com/pricing)
- **Setup and onboarding:**
  - Foodics SAR 1,500 implementation fee: **UNVERIFIED** (review). — [lkwjd](https://lkwjd.com/foodics-review)
  - Odoo Egypt partner implementation: EGP 40k–300k in the first year. — [2b-cs](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)
  - Daftra: "no setup". — [Daftra plans](https://www.daftra.com/plans)
- **Hardware:**
  - Foodics KSA: "Hardware Included, no upfront payments", with the quote based on chosen hardware. — [Foodics KSA](https://www.foodics.com/pricing/)
  - Rewaa: device-set discounts of 70% off or free on 2-year plans. — [Rewaa](https://rewaa.com/pricing)
  - Egypt hardware prices (partner list): thermal printer EGP 2,500–5,000, barcode scanner EGP 1,200–3,500, cash drawer EGP 1,500–3,000, complete single terminal **EGP 8,000–17,000 (USD 152–324)**. — [2b-cs](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)

### Inferences
- A 14-day no-card trial is table stakes in Egypt. Annual prepay discounts of about 15–20% are typical, so Daftra's 33% is aggressive.
- Desktop hardware for one terminal (EGP 8k–17k) roughly equals 3–6 months of Foodics Egypt Basic. Hardware bundling or financing is a competitive lever that Foodics already uses in KSA.

### Gaps
- Foodics Egypt setup fees, trial and hardware pricing are not published ("custom quote after a demo"). — [Foodics Egypt pricing](https://www.foodics.com/foodics-pricing-egypt/)
- No free-trial or setup-fee data was found for Marn, Sapaad, Syrve or Qoyod from primary sources.
- The EGP/USD rate is uncertain (52.46 on 10 Oct 2026 vs "below 57" on 27 Oct 2026). Recompute USD figures with the CBE rate on the day of decision.
