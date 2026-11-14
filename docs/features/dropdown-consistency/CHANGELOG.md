# Consistent dropdowns (POS) — changelog
## 2026-10-29 (unreleased, uncommitted, branch fix/dropdown-consistency)
- Changed: the staff editor's role, a combo's category and each option's product, and the terminal pane's admin timeout and shortcut dropdowns now look like the text fields beside them (frame, fill, padding, reading direction) instead of a bare Material underline.
- Refactored: the three identical filter dropdowns (order history, shift history, users) are one `FilterDropdown`; same size, border and keys.
- Unchanged: the role cell in the staff table, the cloud web selects, behaviour of every dropdown.
