---
name: gauntlet-loop-mixingflavors
description: Repeatable Gauntlet Loop skill for MorrisonC/Mixingflavors (Godot 4 hybrid puzzle game). Each run picks one unresolved target from the game's own GameMode roadmap, sets a real named/fetchable/comparable quality bar, runs isolated builder and critic sub-agents against it, and loops until the critic picks "ours" or you stop it. Designed to be invoked over and over across separate Jules sessions — each run either keeps working an in-progress target or advances to the next one.
license: CC-BY-4.0
compatible_agents: [jules, claude-code, gemini-cli, cursor, antigravity]
source_pattern: https://github.com/robonuggets/gauntlet-loop
---

# Gauntlet Loop — Mixing Flavors

Adapted from robonuggets' Gauntlet Loop
(https://github.com/robonuggets/gauntlet-loop): turn a goal into a real
quality bar, split the work, run a builder and a separate harsh critic on
each piece, compare blind, loop until the critic actually picks your work
— never on a round count.

This version is pre-wired to Mixing Flavors' own project structure so you
don't have to restate the goal every time: point it at the repo, tell it
to run, and it figures out what's next from `MASTER_LEVEL_DESIGN.md`'s own
roadmap table and this skill's `state/` log.

## What "run it over and over" does

Each invocation:
1. Reads `assets/targets.yaml` (mirrors the GameMode roadmap table in
   `MASTER_LEVEL_DESIGN.md`) and `state/` to find the first target that
   is neither `won` nor `human_flagged`.
2. If that target has no bar picked yet, proposes 2–3 bars for it (see
   below) and stops, waiting for you to pick one — same as the original
   skill's interactive step.
3. If a bar is already picked (recorded in `state/<target>.yaml`), runs
   the builder/critic loop for that target, appending each round's result
   to the state file, and stops when the critic picks "ours" or a `STOP`
   file appears in the repo root.
4. On a win, marks the target `won` and exits — the *next* invocation
   automatically starts the next unresolved target from the roadmap. This
   is what makes "run it over and over" work across separate sessions:
   the state directory is the memory, not the conversation.

Nothing here auto-commits to `main` — the builder should work on a branch
or PR per target, consistent with how this repo already runs (25 open
PRs as of this writing use exactly that pattern).

## Step 1 — Pick a target

Run `scripts/list_targets.py`. It prints targets from
`assets/targets.yaml` in roadmap order, skipping anything already `won`
or `human_flagged` in `state/`. Take the first one.

Current targets (mirrors `MASTER_LEVEL_DESIGN.md` Section 4's roadmap —
update `assets/targets.yaml` if the roadmap table changes):

| Target | Status in repo | Core script |
|---|---|---|
| `Picross3D` | Playtested — good first gauntlet target since it already has real content to compare | `VoxelGrid3D.gd` |
| `DetectiveCrimeScene` | Draft | TBD |
| `EscapeGauntlet` | Blockout | TBD |
| `TimeShiftPalimpsest` | Draft | TBD |

## Step 2 — Propose a bar (Named / Fetchable / Comparable)

Per the source pattern, refuse to proceed with a vague bar. Every bar
must be:
- **Named** — an actual shipped puzzle game or mode, not a category
  ("juicy voxel puzzle feedback," not "good game feel").
- **Fetchable** — something the critic sub-agent can actually screenshot,
  play, or read footage/reviews of. If it can't be fetched, the critic
  will hallucinate the comparison and approve everything — this is the
  single most common failure mode of this pattern.
- **Comparable** — close enough in genre/format that a blind side-by-side
  judgment is meaningful.

Suggested bar candidates by target (starting points — verify each is
still live and fetchable before locking one in):

- **Picross3D** → a specific well-regarded 3D voxel/nonogram puzzle
  title's actual gameplay footage or store page screenshots (e.g. search
  "3D nonogram voxel puzzle game" and pick a named, specific result —
  don't default to a category).
- **DetectiveCrimeScene** → a named point-and-click / clue-based
  investigation game's actual scene screenshots.
- **EscapeGauntlet** → a named time-pressure puzzle game's actual
  captured playthrough clip or screenshots.
- **TimeShiftPalimpsest** → a named "past/present overlay" puzzle
  mechanic from a specific shipped game (this sub-genre is narrower —
  it's fine if the closest fetchable match is only partially similar;
  say so honestly rather than force a weak comparison).

Offer 2–3 candidate bars for the chosen target, each with why it's a fair
comparison, and wait for a pick — write the picked bar into
`state/<target>.yaml` before proceeding. See
`resources/bar-selection-guide.md` for the full checklist.

## Step 3 — Write the one prompt

Once a bar is picked, write ONE short prompt (~150 words) in the shape
below and hand it to a fresh session/subagent — same structure as the
source skill:

```
Build/improve [TARGET] in Mixing Flavors (Godot 4, scenes/<target>.tscn)
to the level of [NAMED BAR]. Split the work into the smallest
independently-judgeable pieces (per puzzle mechanic, per UI panel, per
feedback/juice pass — whatever the target needs). For each piece, run a
builder and a separate critic. The critic gets fresh context, the
reference bar, and the rendered artifact only — never the builder's
notes. It opens both side by side with labels stripped and picks one.
Not a score. If the bar wins, hand the critic's single named gap back to
the builder and go again. Keep looping until the critic picks ours, or
until a STOP file appears in the repo root. Log every round to
state/[TARGET].yaml.
```

## Step 4 — Run the loop

`scripts/run_gauntlet.sh <target>` drives steps 2–4 mechanically (state
tracking, capture, logging) but the actual builder/critic sub-agent
invocation is a hook — see the `TODO` in that script. Wire it to
whatever your runtime's sub-agent spawn mechanism is (a fresh Jules
session/task is the natural fit here, since Jules is already how this
repo receives isolated units of work via its 25 open PRs).

## Capture mechanism (specific to this repo)

Mixing Flavors already ships a Godot web export (`build/web/`) and a
Playwright test setup (`playwright.config.js`, `tests/playwright/`).
Reuse that instead of building a new screenshot pipeline:

1. `godot4 --headless --export-release "Web" build/web/index.html`
   (Godot's own `--headless` disables the render path entirely — same
   caveat as it would for any engine — so this step only produces the
   exported build, it does not itself take a screenshot.)
2. Serve `build/web/` locally (`server.js` already in the repo, or
   `python3 -m http.server`), then use Playwright (already a project
   dependency) to load the specific game mode and screenshot it. This is
   real browser rendering, not a mock — same category of artifact as the
   critic in the source pattern expects ("screenshot it, read it, run
   it, or open it").

See `scripts/capture_target.sh`.

## Guardrails (see `resources/critic-instructions.md` for the full list)
- No fixed round cap, per the source pattern — the loop only exits on a
  win or a `STOP` file. Every round is still logged to
  `state/<target>.yaml` so a long-running loop stays visible instead of
  silent.
- Builder and critic must be genuinely separate invocations — the critic
  never sees the builder's notes, only the bar and the rendered artifact.
- A vague or unfetchable bar is a hard stop for that target, not a soft
  warning.
