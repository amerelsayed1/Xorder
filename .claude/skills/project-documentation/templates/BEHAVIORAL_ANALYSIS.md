# Behavioral analysis: <feature title>

Status: **UNVALIDATED (from reading).** This file is excluded from `/project-documentation validate` and can never make a feature `validated`. Treat every statement as a lead: re-trace the code before relying on it, and say so in any plan or review that uses it.
Verified against (when written): <date> · cloud `<sha>` · POS `<sha>`
Path prefixes as in `FEATURE.md`.

What belongs here: conclusions that need a trace across more than one code location or over time, or that predict behavior nobody tested: multi-pass or multi-step scenarios, ordering and timing guarantees, concurrency, failure cascades, consequences of divergences between two implementations, topology consequences, and any "can", "would", "never clears" statement. What does NOT belong here: a fact about one location (`path:line`) or a test assertion; those stay in `FEATURE.md` and are validated.

Each entry: a title, the claim, the trace (numbered steps with `path:line`), the confidence (high / medium / low) and what would confirm it (test or experiment).

## <entry title>
- Claim:
- Trace:
- Confidence:
- Would be confirmed by:
