# Workflows: <feature title>

Verified against: <date> · cloud `<HEAD>` · POS `<HEAD>`
Optional sixth-plus file of a feature folder. One section per user-visible journey. Every step cites the code that performs it or is marked UNVERIFIED.

## Workflow index
| ID | Name | Actor | Trigger | Applications involved |
| --- | --- | --- | --- | --- |
| WF-1 | | | | cloud / POS / Vue app |

## WF-1: <name>
**Actor and permission:** 
**Preconditions:** 
**Postconditions and persisted state:** 

| Step | Actor / system | Action | Code (`path:line`) | Result and state change | Failure branch |
| --- | --- | --- | --- | --- | --- |
| 1 | | | | | |

**Sequence across applications** (only when more than one system participates):
```
Actor -> POS screen -> domain service -> local DB
POS -> cloud endpoint -> service -> cloud DB
```

**State machine** (when the workflow changes a status; list states from the enum and allowed transitions with the code that guards them):
| From | To | Guard / permission | Evidence |
| --- | --- | --- | --- |

**Edge cases and recovery:** 
**Tests covering this workflow:** 

## Gaps
(Steps documented elsewhere but not found in code; implemented steps with no UI; UNVERIFIED items.)
