# PIN entry from the physical keyboard — changelog
## 2026-10-28 (unreleased, uncommitted, branch fix/pos-pin-keyboard)
- Fixed: tapping a key on the on-screen PIN pad now hands the keyboard to the pad, so the rest of the PIN can be typed (lock screen, sign-in and shift-open dialogs).
- Added: a one-line hint under the name box on the lock screen and the sign-in/shift dialogs, "Press Enter or Tab, then type the PIN" (en, ar).
- Unchanged: auto-submit at four digits, the attempt limiter, the Enter/Tab handoff, the supervisor dialog.
