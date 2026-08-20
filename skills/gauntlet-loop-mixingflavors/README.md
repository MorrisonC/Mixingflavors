# gauntlet-loop-mixingflavors

A repeatable Gauntlet Loop for [MorrisonC/Mixingflavors](https://github.com/MorrisonC/Mixingflavors)
(Godot 4 hybrid puzzle game), following
[robonuggets/gauntlet-loop](https://github.com/robonuggets/gauntlet-loop)'s
pattern: pick a real named/fetchable/comparable bar, run isolated builder
and critic sub-agents against it, loop until the critic actually picks
your work — never on a fixed round count.

Packaged per the [Agent Skills structure](https://github.com/google-labs-code/jules-skills)
so it installs the same way as any other Jules skill.

## Install
```bash
npx skills add <this-repo> --skill gauntlet-loop-mixingflavors --global
```

## Designed to be run over and over

Each invocation either continues an in-progress target or — once that
target wins — automatically picks up the next one from
`assets/targets.yaml` (which mirrors the roadmap table in
`MASTER_LEVEL_DESIGN.md`). State lives in `state/`, not in the
conversation, so this works across separate Jules sessions with no
memory of prior runs required.

## Quick start
```bash
bash scripts/doctor.sh                       # check Godot/Playwright/yq are set up
python3 scripts/list_targets.py              # see what's next
# ... propose bars for that target, get one picked (SKILL.md step 2) ...
# write the picked bar into state/<target>.yaml (see state/Picross3D.yaml.example)
bash scripts/run_gauntlet.sh Picross3D       # run the loop for that target
```

## Wiring to your agent runtime
`scripts/run_gauntlet.sh` has two hooks, `invoke_builder` and
`invoke_critic`, marked `TODO`. For this repo, a fresh Jules
session/task per round is the natural fit — that's already how the repo
receives isolated units of work (see its open PRs). Wire the hooks to
that; the rest of the script (state tracking, capture, round logging) is
runtime-agnostic.

## Honest caveat
Godot's `--headless` flag disables rendering entirely (same category of
limitation as most engines' headless modes) — it only produces the web
export in this pipeline, not a screenshot. The actual capture step reuses
this repo's existing Playwright setup against the served web build, which
is real browser rendering and was already a project dependency, so no new
screenshot infrastructure was invented for this.
