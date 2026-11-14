# Terminal lists say whether Delete can succeed — pos-terminal-delete-visibility

Status: drafted · 2026-11-03 · Source: QA item XORD-042 (`docs/qa/XORDER_QA_FINDINGS.md`), owner go "Yes, log and fix" · Verified against: xorder-cloud `775bf0f` plus this uncommitted change

1. **Summary.** The Back Office offered Delete on every revoked POS device and learned only after confirmation that a device with sales history is kept. The lists now say so in advance.
2. **Why.** An owner cleaning up old tills (any venue model) met a dead button and a "Something went wrong" message for a rule that is working as designed.
3. **Goal.** Delete appears only when the server would accept it.
4. **Roles.** Unchanged: `pos.provision` on the dashboard; the Super Admin fleet capability on the tenant page.
5. **Today (after the change).** Rule: `PosProvisioningService::delete` (unchanged). Flag: `PosProvisioningService::withMoneyHistory`; field in `PosTerminalResource`.
6. **Scope.** In: both terminal lists and both pages. Out: changing the delete rule, archiving or hiding revoked devices.
7. **Rules.** BR-1 a terminal with an order or a traded shift (float, count or close) is never deleted. BR-2 the flag uses the same predicate as delete.
8. **Acceptance criteria.** AC-1 to AC-6 in `TECHNICAL.md`.
9. **Edge cases.** A terminal that trades after the list loads: delete is refused as before and the page switches to the kept note.
10. **Impact.** Additive field on two dashboard endpoints; no schema, no POS contract.
11. **Risks.** PostgreSQL behaviour read, not run.
12. **Tests.** `TEST_PLAN.md`, `TEST_REPORT.md`.
13. **Decisions.** 2026-11-03 owner: option 1 (flag in the list) over changing only the error message.
