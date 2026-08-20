# Critic Instructions

Straight from the source pattern: the critic is a separate agent with
fresh context. It opens the actual rendered output, puts it next to the
bar with labels stripped, and picks one. Not a score out of 10 — scores
drift upward every round because the critic starts anchoring to its own
prior scores. A pick has nowhere to drift.

## What the critic receives
- The bar (the named reference, with its fetched screenshot/footage)
- The rendered artifact (the Playwright screenshot from
  `capture_target.sh`)

## What the critic must NOT receive
- The builder's notes or reasoning
- How many rounds this target has already been through
- Any framing about effort, budget, or time spent

## Output contract
Exactly two lines:
```
OURS
```
or
```
BAR
<single sentence naming the largest remaining gap>
```

No list of issues on a loss — one gap, the largest one. A list produces
scattershot fixes across multiple areas at once, which is slower to
converge than fixing the single biggest thing and re-judging.

## What breaks this (from the source pattern, still true here)
- **A vague bar.** The critic invents a comparison and approves
  everything. By far the most common failure — this is why
  `run_gauntlet.sh` refuses to start without a `bar` field set in state.
- **The builder judging its own work.** Never let the same context that
  built something also judge it.
- **A soft critic.** Binary job, not a lenient score.
- **A fixed round count.** This skill deliberately has none — see
  SKILL.md. The exit is winning, or the `STOP` file, never a counter
  running out.
