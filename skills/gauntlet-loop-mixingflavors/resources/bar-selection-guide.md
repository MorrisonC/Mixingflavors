# Bar Selection Guide

Straight from the source pattern (robonuggets/gauntlet-loop): a bar must
pass all three checks before you lock it in. If it fails any one, the
loop will produce garbage — the critic either hallucinates a comparison
or agrees with everything the builder does.

## The three checks

1. **Named** — a specific, real thing. "A polished 3D puzzle game" is not
   a bar. "Voxel Sweeper's chisel-and-reveal feedback loop" is.
2. **Fetchable** — the critic sub-agent must be able to actually get it:
   screenshot a store page, load a web build, watch a captured
   playthrough clip, read an actual review with images. If it can only
   be described from memory, it's not fetchable.
3. **Comparable** — close enough in genre and format that a side-by-side,
   labels-stripped judgment means something. Comparing a 3D voxel puzzle
   against a 2D match-3 UI isn't a fair bar even if both are "puzzle
   games."

## Applying this to Mixing Flavors' targets

Each target in `assets/targets.yaml` has a `notes` field with target-
specific guidance. General pattern for this project:

- Prefer bars with **actual footage or screenshots you can point to a
  URL for** — a specific game's Steam page, itch.io page, or a specific
  YouTube playthrough timestamp — over just naming a well-known title
  and assuming everyone knows what it looks like.
- For the Draft/Blockout targets (`DetectiveCrimeScene`, `EscapeGauntlet`,
  `TimeShiftPalimpsest`), it's fine — and more honest — to pick a bar
  that's a partial match on mechanic rather than genre, and say so in the
  proposal. A forced "best available" comparison beats no comparison, as
  long as the gap is named honestly.
- Don't reuse the same bar across two different targets just because
  it's convenient — a bar picked for `Picross3D`'s voxel-chiseling feel
  isn't automatically valid for `EscapeGauntlet`'s time-pressure feel,
  even though both are puzzle modes in the same game.

## Proposal format

When proposing bars (SKILL.md step 2), give 2–3 candidates like this:

```
Target: Picross3D

1. [Named Game X] — https://example.com/store-page
   Why: closest match on the chisel/reveal core loop; has real
   screenshots of the exact voxel-corruption-style feedback we're
   comparing against.

2. [Named Game Y] — https://example.com/playthrough-clip
   Why: different visual style but the clearest example of "alchemy/
   recolor" as a puzzle-solving tool, which is the specific mechanic
   in question here.
```

Wait for a pick. Write only the picked bar into `state/<target>.yaml`.
