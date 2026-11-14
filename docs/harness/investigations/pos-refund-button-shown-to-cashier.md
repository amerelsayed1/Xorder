# pos-refund-button-shown-to-cashier — the Refund button is drawn for a cashier who does not hold `order.refund`

Status: investigated · 2026-10-27 · Confidence: **confirmed** for the mechanism and the reproduction; the *intended* behaviour is **contested** by three sources in the repo (section 3) and needs an owner decision · Verified against: `xorder-pos` `c67c754` + one uncommitted file (`test/data/local_bootstrap_test.dart`, from XORD-035, unrelated).

## 1. Symptom

- App: `xorder-pos`, Orders screen (`/orders`, also the back office's Sales tab). Signed in as a cashier ("السيد · كاشير"), an order selected (`MAIN-2026-000005`, paid, 472.42 EGP).
- Actual: the action row under the order shows **معاينة** (Preview), **إعادة طباعة الفاتورة** (Reprint) and a red **استرجاع** (Refund).
- Expected (reporter): the cashier role is not allowed to refund, so the button should not appear.
- Reporter's screenshot only; no log. Frequency: every order, every cashier without `order.refund` (the default cashier role never holds it).

## 2. How it was reproduced

Throwaway copy of the existing cashier test in the scratchpad package (`scratchpad/repro/test/cashier_repro_test.dart`, imports the repo by path; nothing added to the repo), printing the real gate decision and the widgets on screen for the test fixture cashier (role `cashier`, capabilities `{operate}`):

```
REPRO cashier decisions: refund=NeedsOverride reprint=NeedsOverride cashier holds refund=false
REPRO Refund button on screen for the cashier: 1; Reprint: 1
00:01 +1: All tests passed!
```

So the cashier does not hold the capability, the decision is "needs override", and the button is drawn. Not run: the real app, a real database, the refund sheet for a cashier (see section 7, no existing widget test covers it).

## 3. Root cause

**Mechanism.** `lib/features/history/presentation/order_detail_pane.dart:588-596` decides visibility with `Authorization.check(by, PosCapability.orderRefund) is! Denied`. `Authorization.check` (`lib/domain/services/authorization.dart:151-160`) returns `Allowed` if the person holds the capability, `NeedsOverride` if they lack it but a supervisor may lend it (`PosCapability.mayBeLent`), and `Denied` only for capabilities that cannot be lent. `orderRefund` is on the lendable list (`lib/domain/models/permissions.dart:222-230`) and is not CRITICAL, so for a cashier the answer is always `NeedsOverride`, never `Denied`. `is! Denied` is therefore true for every role, and the button is always built (`mayRefund && Expanded(...)`, lines 628-646).

**Why it looks like a bug: three sources disagree about the intent.**
1. The pane's own comment (`order_detail_pane.dart:~568-572`): refund is "hidden rather than greyed for a cashier who never holds `order.refund`". The code does not do this. This is the cause of the mismatch.
2. The project's permission design, `lib/core/ui/widgets/permission_gate.dart:9-45`: a lendable capability must be **shown enabled** and open the manager-approval prompt ("A cashier at a queue needs to press *Discount* and have a manager arrive at the prompt"); `hidden` is for CRITICAL capabilities only. The doc says this is "the only correct way to render a gated control". The pane does not use `PermissionGate`; it makes its own private decision, which is exactly what that doc warns against.
3. The reporter's expectation: hidden.

So the current behaviour matches (2) by accident of `is! Denied`, contradicts (1), and surprises (3).

**What the button does when a cashier presses it (read, not run).** `_refundFlow` opens `RefundSheet` (`order_detail_pane.dart:676-686`). On Issue the sheet calls `requestPermission(... orderRefund ...)` (`refund_sheet.dart:~657`), which for `NeedsOverride` opens `SupervisorOverrideDialog` (`supervisor_override.dart:~66-88`) and only proceeds with a supervisor's PIN and a recorded approval. The repository then re-checks: `Authorization.require(by, orderRefund, approval: ...)` (`postgres_refunds_repository.dart:72-78`). **A cashier cannot refund alone; this is a visibility and design question, not a permission bypass.**

**Cause vs symptom vs contributing conditions.** Symptom: Refund visible to a cashier. Cause: `is! Denied` treats "needs a supervisor" as "allowed to see". Contributing: a stale comment; the pane bypassing `PermissionGate`; and the tests (below) written as `Denied ? findsNothing : findsOneWidget`, which restate the implementation and so cannot detect a wrong rule. Also a UX consequence of design (2): the approval prompt comes at the end of the refund sheet, after the cashier has picked lines, a reason and a tender, not when the button is pressed.

**Correction to an earlier chat answer.** I said Reprint is also shown to a cashier who lacks it. The default cashier role **holds** `receipt.reprint` (`permissions.dart`, `cashier` set), so Reprint is legitimately allowed there. It is the same code pattern (`is! Denied`, line 596) and would show for a custom role without it, but for a default cashier only Refund is affected.

## 4. Evidence and alternatives ruled out

- *Missing permission check / bypass* — ruled out by reading: two layers enforce approval (sheet prompt, repository `require`). Not exercised by a test (section 7).
- *Role misconfigured to include refund* — ruled out for the fixture and the default set: `cashier` has no `order.refund` (`permissions.dart` cashier set; fixture `{operate}`; printed `holds refund=false`). The reporter's actual role on their till was not inspected; a custom role could hold it, in which case the button is correctly allowed.
- *Wrong person asked (acting vs signed-in)* — the pane asks `actingStaffProvider` (`order_detail_pane.dart:586`), correct for the back office Sales tab; in the screenshot both are the cashier.
- Same pattern elsewhere: `is! Denied` appears **only** at `order_detail_pane.dart:589` and `:596`; every other gate in `lib/` uses `.isAllowed` or `PermissionGate`.
- Existing tests mirror the code: `test/features/order_history_test.dart:1631` and `test/features/back_office_sales_test.dart:413` both assert `Authorization.check(person, capability) is Denied ? findsNothing : findsOneWidget`. They pass today with the button shown (reproduction above).

## 5. Impact

- Who: any signed-in role that lacks `order.refund` and has an order open on `/orders` or in Back Office > Sales: cashiers in all four venue models.
- Cafés (counter, queue): the "wrong drink, give it back" refund is routine; the design wants the cashier to be able to start it and call a supervisor. Restaurants: a floor manager typically approves. Food trucks: usually one person who holds everything, so no visible difference. Cloud kitchens: no counter, refunds are a back-office act, so a button a cashier cannot finish is noise.
- Data, money, tenancy: none affected; no refund can be issued without a second person's approval or the capability. Not a security finding; **not routed to `/security-audit`** (confirm once the sheet path is tested).
- Apps: POS only. The cloud has no equivalent screen for this button.

## 6. Fix options

Narrowest first. **The owner must pick the intended behaviour first (Q1).**

**A. Hide Refund unless the acting person holds `order.refund`** (`is! Denied` -> `.isAllowed` at `order_detail_pane.dart:589`; same for Reprint at `:596` if the same rule is wanted). Two-line change, matches the comment and the report. Trade-off: removes the "cashier starts a refund and a supervisor taps a PIN" path; the supervisor must sign in on the till (or use Back Office > Sales) to refund. Contradicts `permission_gate.dart` guidance for lendable capabilities, so that doc or the rule should be amended in the same change.

**B. Keep it visible, as the permission design says, and make it honest.** Render through `PermissionGate(behaviour: GateBehaviour.approval)`, ask for the supervisor **when the button is pressed** (before the sheet), and correct the stale comment. Trade-off: the cashier still sees a button they cannot finish alone (the complaint), but the flow stops wasting their time on a form that will end in a PIN prompt. Larger change (sheet flow ordering, approval spent once).

**C. A per-restaurant setting** ("cashiers may start refunds with approval" on/off). Matches both camps; needs a settings row and permission; not narrowest. Not recommended now.

Recommendation: **A** for the stated complaint (cheap, reversible, hides what the person cannot do), with the permission-gate doc updated to say refund is the one lendable action shown only to holders; revisit B if cafés ask for the queue flow.

Must NOT change: `Authorization.check` semantics and its lendable list; the repository's `Authorization.require`; the above-threshold second-person rule; the back office Sales tab's "acting person" rule (the owner at the door still sees Refund); the existing "disabled when nothing is left to refund" behaviour.

## 7. Tests the fix needs

- Rewrite the two mirror tests so they assert the **rule**, not the code: for option A, a cashier fixture `{operate}` sees **no** Refund and a supervisor/manager sees it (`order_history_test.dart:1580-1640` group and `back_office_sales_test.dart:~395-420`). Keep a case where a supervisor without order-history rights still behaves as before.
- Add the missing sheet-level test: a person who lacks `order.refund` reaching `RefundSheet` (if option B, or any other entry) is stopped at the supervisor PIN and the repository refuses without an approval (`test/features/refund_sheet_test.dart`; `test/domain/authorization_test.dart:243` covers the threshold case only).
- Regression guard for the pattern: a small test that `NeedsOverride` for a lendable capability is not rendered as "allowed" in `OrderDetailPane` actions.
- Existing suites to run: `flutter test test/features/order_history_test.dart test/features/back_office_sales_test.dart test/features/refund_sheet_test.dart test/domain/authorization_test.dart`, then `flutter analyze` and the full `flutter test`.

## 8. Approvals the fix needs

- Option A narrows what a role sees: **permission change that narrows access, needs explicit approval** (workspace rule). No migration, no contract, no order-state or payment change, nothing reaches `xorder-cloud` `main`; POS-only, ships with the next POS build.
- Option B changes the order of a refund flow (approval before the form): money-adjacent, review with the refund owner before building.

## 9. Open questions and what could not be verified

- **Q1 (blocking).** Hide for roles that cannot refund alone (A), or keep with the approval prompt (B)? The reporter's wording favours A; the project's own permission doc favours B.
- **Q2.** Should Reprint follow the same rule for roles without `receipt.reprint`? (Default cashier holds it, so no visible change today.)
- Not verified: the reporter's actual role and capabilities on their till; the real refund sheet for a cashier in a running app; the Arabic layout of the row (the screenshot shows it fine); whether a cloud-provisioned role set (`pos.refund` mapping, `permissions.dart:281`) gives cashiers refund on any live restaurant (not checked; no production access).
- Docs: `docs/features` has no page for `pos-order-history`/refund gating (inventory row `pos-refunds` is `pending`, UNVERIFIED); nothing there contradicts the above.

Next action: answer Q1, then `/implement docs/harness/investigations/pos-refund-button-shown-to-cashier.md`.
